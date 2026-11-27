# frozen_string_literal: true

#
# Copyright:: NodeRings
# License:: Apache-2.0
#
# The Bolt inventory plugin: turns NodeRings virtual machines into Bolt
# targets. It runs inside the resolve_reference task, outside Puppet, so it
# only uses the plain-Ruby API client.

require_relative 'client'
require_relative 'compute'

module PuppetX
  module Noderings
    # Builds Bolt targets from the VMs of an organization.
    module BoltInventory
      # Where each target field comes from when target_mapping leaves it out.
      DEFAULT_MAPPING = { 'name' => 'hostname', 'uri' => 'ipv4' }.freeze
      TARGET_KEYS = %w[name uri alias config facts vars features].freeze
      # The VM fields a mapping can refer to, also exposed as facts.noderings.
      DATA_FIELDS = %w[
        id hostname ipv4 ipv6 power_state distro plan_code plan_id region_id region_city
        region_country provider_name billing_type firewall_ruleset_id tags cpus memory_mb
        disk_mb instant_app
      ].freeze

      module_function

      # params are the task parameters: token, api_url, organization_id,
      # tags, power_states, name_pattern, target_mapping. Returns the targets.
      def resolve(params, env: ENV, transport: nil, sleeper: nil)
        params = (params || {}).transform_keys(&:to_s)
        token = first_present(params['token'], *TOKEN_ENV_VARS.map { |v| env[v] })
        unless token
          raise UsageError, 'No NodeRings API token: set the token option of the noderings plugin ' \
                            '(for example from the env_var plugin) or the NODERINGS_TOKEN environment variable.'
        end

        client = Client.new(
          token: token,
          api_url: first_present(params['api_url'], env['NODERINGS_API_URL']),
          organization_id: first_present(params['organization_id'], env['NODERINGS_ORGANIZATION_ID']),
          user_agent: 'puppet-noderings-bolt-inventory',
          transport: transport, sleeper: sleeper
        )
        mapping = DEFAULT_MAPPING.merge(validate_mapping(params['target_mapping'] || {}))
        filter = filters(params)
        targets = client.list_virtual_machines.map { |machine| vm_data(machine) }
                        .select { |data| keep?(data, filter) }
                        .filter_map { |data| target(data, mapping) }
        targets.sort_by { |t| [t['name'].to_s, t['uri'].to_s] }
      end

      # The VM as the flat hash that mappings and facts.noderings use.
      def vm_data(machine)
        Compute.view(machine).merge(
          'region_city' => machine['regionCity'],
          'region_country' => machine['regionCountry'],
          'provider_name' => machine['providerName'],
          'cpus' => integer(machine['cpu']),
          'memory_mb' => integer(machine['memory']),
          'disk_mb' => integer(machine['storage']),
          'instant_app' => machine['instantAppSlug'].to_s.empty? ? nil : machine['instantAppSlug'],
        ).slice(*DATA_FIELDS)
      end

      def filters(params)
        states = Array(params['power_states'] || ['running']).map { |s| s.to_s.downcase }
        pattern = params['name_pattern'].to_s
        {
          tags: Array(params['tags']).map(&:to_s),
          states: states.include?('all') ? nil : states,
          pattern: pattern.empty? ? nil : Regexp.new(pattern),
        }
      rescue RegexpError => e
        raise UsageError, "name_pattern is not a valid regular expression: #{e.message}"
      end

      def keep?(data, filter)
        return false if filter[:states] && !filter[:states].include?(data['power_state'])
        return false unless (filter[:tags] - Array(data['tags'])).empty?
        return false if filter[:pattern] && !filter[:pattern].match?(data['hostname'].to_s)

        true
      end

      # One Bolt target, or nil when the mapped name and uri are both empty
      # (a VM that has no address yet).
      def target(data, mapping)
        t = {}
        mapping.each do |key, path|
          value = %w[config facts vars].include?(key) ? map_tree(path, data) : lookup(data, path)
          t[key] = value unless value.nil? || value == ''
        end
        return nil if t['uri'].nil? && t['name'].nil?

        t['name'] ||= t['uri']
        t['facts'] = { 'noderings' => data }.merge(t['facts'] || {})
        t
      end

      # A nested hash of paths -> the same hash with values looked up.
      def map_tree(tree, data)
        tree.each_with_object({}) do |(k, v), out|
          value = v.is_a?(Hash) ? map_tree(v, data) : lookup(data, v)
          out[k] = value unless value.nil?
        end
      end

      # 'hostname' or 'tags.0' -> the value in data.
      def lookup(data, path)
        path.to_s.split('.').reduce(data) do |node, part|
          case node
          when Hash then node[part]
          when Array then part.match?(%r{\A\d+\z}) ? node[part.to_i] : nil
          end
        end
      end

      def validate_mapping(mapping)
        raise UsageError, 'target_mapping must be a hash' unless mapping.is_a?(Hash)

        mapping = mapping.transform_keys(&:to_s)
        unknown = mapping.keys - TARGET_KEYS
        raise UsageError, "target_mapping has unknown keys: #{unknown.join(', ')} (allowed: #{TARGET_KEYS.join(', ')})" unless unknown.empty?

        bad = mapping.reject do |k, v|
          %w[config facts vars].include?(k) ? v.is_a?(Hash) : v.is_a?(String)
        end
        raise UsageError, "target_mapping values must be field names, or hashes for config, facts and vars: #{bad.keys.join(', ')}" unless bad.empty?

        mapping
      end

      def first_present(*values)
        values.map { |v| v.to_s.strip }.find { |v| !v.empty? }
      end

      def integer(value)
        Integer(value.to_s, 10)
      rescue ArgumentError
        nil
      end
    end
  end
end
