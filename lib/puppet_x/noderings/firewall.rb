# frozen_string_literal: true

#
# Copyright:: NodeRings
# License:: Apache-2.0
#
# Firewall rule validation, conversion and reconciliation.

require 'ipaddr'

require_relative 'client'

module PuppetX
  module Noderings
    module Firewall
      PROTOCOLS = %w[
        tcp udp sctp ipv6 icmp icmpv6 esp ah ipsec gre ipip vxlan l2tp geneve any igmp ggp
        ipencap st egp igp pup hmp xns_idp rdp iso_tp4 dccp xtp ddp idpr_cmtp ipv6_route
        ipv6_frag idrp rsvp skip ipv6_icmp ipv6_nonxt ipv6_opts vmtp eigrp ospf ax_25 etherip
        encap pim ipcomp vrrp isis fc mobility_header udplite mpls_in_ip hip shim6 wesp rohc
      ].freeze
      PORT_PROTOCOLS = %w[tcp udp sctp dccp udplite].freeze
      DIRECTIONS = %w[ingress egress].freeze
      ACTIONS = %w[accept drop].freeze
      MAX_RULES = 50
      PORTS_RE = %r{\A(\d{1,5})(?:-(\d{1,5}))?\z}.freeze
      ENDPOINT_KEYS = %w[cidrs address_group_ids address_groups vm_tags].freeze

      module_function

      # Rules as users write them: string or symbol keys, any nesting.
      def stringify(value)
        case value
        when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify(v) }
        when Array then value.map { |v| stringify(v) }
        else value
        end
      end

      def prefix(value)
        IPAddr.new(value.to_s.strip)
      end

      def cidr(value)
        addr = prefix(value)
        "#{addr}/#{addr.prefix}"
      end

      def canonical_cidr(value)
        cidr(value)
      rescue ArgumentError
        value.to_s.strip.downcase
      end

      def endpoint_count(endpoint)
        ENDPOINT_KEYS.sum { |k| Array(endpoint[k]).length }
      end

      # An error message for one rule, or nil.
      def validate_rule(rule, index)
        where = "rule #{index}"
        return "#{where} must be a Hash" unless rule.is_a?(Hash)
        return "#{where}: direction must be one of #{DIRECTIONS.join(', ')}" unless DIRECTIONS.include?(rule['direction'].to_s)
        return "#{where}: action must be one of #{ACTIONS.join(', ')}" unless ACTIONS.include?(rule['action'].to_s)

        protocol = (rule['protocol'] || 'tcp').to_s
        return "#{where}: unknown protocol #{protocol.inspect}; use one of #{PROTOCOLS.join(', ')}" unless PROTOCOLS.include?(protocol)

        src = rule['source'] || {}
        dst = rule['destination'] || {}
        if endpoint_count(src).zero? && endpoint_count(dst).zero?
          return "#{where} needs a source or destination. To match any IPv4 address use cidrs: ['0.0.0.0/0']; " \
                 "for IPv6 add a second rule with ['::/0']."
        end
        [['source', src], ['destination', dst]].each do |side, e|
          cidrs = Array(e['cidrs'])
          cidrs.each do |c|
            prefix(c)
          rescue ArgumentError
            return "#{where} #{side}: #{c.inspect} is not an IP address or CIDR"
          end
          anys = cidrs.select { |c| prefix(c).prefix.zero? }
          if !anys.empty? && endpoint_count(e) > 1
            return "#{where} #{side}: #{anys.join(' and ')} matches every address, so it must be the only " \
                   'entry on that side. Write two rules to match both IPv4 and IPv6.'
          end
        end
        %w[source_ports destination_ports].each do |name|
          v = rule[name]
          next if v.nil?
          return "#{where}: protocol #{protocol} has no ports; #{name} only works with #{PORT_PROTOCOLS.join(', ')}" unless PORT_PROTOCOLS.include?(protocol)

          m = PORTS_RE.match(v.to_s.strip)
          lo = m ? m[1].to_i : 0
          hi = m ? (m[2] || m[1]).to_i : 0
          unless m && lo >= 1 && lo <= hi && hi <= 65_535
            return "#{where}: #{name} #{v.inspect} must be one port such as 443 or one range such as " \
                   '8000-8100. Lists such as 80,443 are not supported; write one rule per port or range.'
          end
        end
        nil
      end

      def endpoint_to_api(endpoint, group_ids_by_name)
        return if endpoint.nil? || endpoint.empty?

        out = {}
        cidrs = Array(endpoint['cidrs']).map { |c| canonical_cidr(c) }
        out['ips'] = { 'ips' => cidrs.sort } unless cidrs.empty?
        ids = Array(endpoint['address_group_ids']).map(&:downcase)
        Array(endpoint['address_groups']).each do |name|
          raise UsageError, "no NodeRings firewall address group is named #{name}" unless group_ids_by_name.key?(name)

          ids << group_ids_by_name[name].downcase
        end
        out['addressGroupIds'] = { 'addressGroupIds' => ids.uniq.sort } unless ids.empty?
        tags = Array(endpoint['vm_tags'])
        out['vmTags'] = { 'tags' => tags.uniq.sort } unless tags.empty?
        out.empty? ? nil : out
      end

      def rule_to_api(rule, group_ids_by_name = {})
        body = {
          'action' => "FIREWALL_ACTION_#{rule['action'].to_s.upcase}",
          'protocol' => "FIREWALL_PROTOCOL_#{(rule['protocol'] || 'tcp').to_s.upcase}",
          'direction' => "FIREWALL_DIRECTION_#{rule['direction'].to_s.upcase}",
        }
        src = endpoint_to_api(rule['source'], group_ids_by_name)
        dst = endpoint_to_api(rule['destination'], group_ids_by_name)
        body['source'] = src if src
        body['destination'] = dst if dst
        body['sourcePorts'] = rule['source_ports'].to_s.strip unless rule['source_ports'].to_s.empty?
        body['destinationPorts'] = rule['destination_ports'].to_s.strip unless rule['destination_ports'].to_s.empty?
        body
      end

      def endpoint_key(endpoint)
        return '' if endpoint.nil? || endpoint.empty?

        parts = []
        ips = Array((endpoint['ips'] || {})['ips']).map { |c| canonical_cidr(c) }.sort
        parts << "ips=#{ips.join(',')}" unless ips.empty?
        groups = Array((endpoint['addressGroupIds'] || {})['addressGroupIds']).map(&:downcase).sort
        parts << "groups=#{groups.join(',')}" unless groups.empty?
        tags = Array((endpoint['vmTags'] || {})['tags']).sort
        parts << "tags=#{tags.join(',')}" unless tags.empty?
        parts.join(';')
      end

      # Compares two API rule bodies, ignoring list order.
      def same_rule?(left, right)
        left['action'] == right['action'] && left['protocol'] == right['protocol'] && left['direction'] == right['direction'] &&
          left['sourcePorts'].to_s == right['sourcePorts'].to_s &&
          left['destinationPorts'].to_s == right['destinationPorts'].to_s &&
          endpoint_key(left['source']) == endpoint_key(right['source']) &&
          endpoint_key(left['destination']) == endpoint_key(right['destination'])
      end

      def endpoint_view(endpoint)
        e = endpoint || {}
        out = {}
        ips = Array((e['ips'] || {})['ips'])
        out['cidrs'] = ips.sort unless ips.empty?
        groups = Array((e['addressGroupIds'] || {})['addressGroupIds'])
        out['address_group_ids'] = groups.sort unless groups.empty?
        tags = Array((e['vmTags'] || {})['tags'])
        out['vm_tags'] = tags.sort unless tags.empty?
        out
      end

      # The user-facing form of an API rule (with or without id and position).
      def rule_view(api_rule)
        body = api_rule['rule'] || api_rule
        out = {
          'direction' => PuppetX::Noderings.trim_enum(body['direction'], 'FIREWALL_DIRECTION_'),
          'action' => PuppetX::Noderings.trim_enum(body['action'], 'FIREWALL_ACTION_'),
          'protocol' => PuppetX::Noderings.trim_enum(body['protocol'], 'FIREWALL_PROTOCOL_'),
        }
        src = endpoint_view(body['source'])
        dst = endpoint_view(body['destination'])
        out['source'] = src unless src.empty?
        out['destination'] = dst unless dst.empty?
        out['source_ports'] = body['sourcePorts'] unless body['sourcePorts'].to_s.empty?
        out['destination_ports'] = body['destinationPorts'] unless body['destinationPorts'].to_s.empty?
        out
      end

      # True when the ruleset's rules differ from desired (contents or order).
      def rules_differ?(current, desired)
        return true if current.length != desired.length

        current.zip(desired).any? { |c, d| !same_rule?(c['rule'] || {}, d) }
      end

      # Makes the ruleset hold exactly `desired`, in order, and returns the final rules.
      #
      # Matching rules are kept, changed ones are updated in place, missing ones
      # are created and extra ones deleted; then rules are moved into order. This
      # keeps rule IDs stable where possible.
      def reconcile(client, ruleset_id, desired)
        current = client.list_firewall_rules(ruleset_id)
        ids = Array.new(desired.length)
        claimed = []
        desired.each_with_index do |d, i|
          c = current[i]
          next unless c && !claimed.include?(c['id']) && same_rule?(c['rule'] || {}, d)

          ids[i] = c['id']
          claimed << c['id']
        end
        # A second pass, not merged with the first: every rule keeps its own
        # position before any rule claims a match from elsewhere.
        desired.each_with_index do |d, i| # rubocop:disable Style/CombinableLoops
          next if ids[i]

          c = current.find { |x| !claimed.include?(x['id']) && same_rule?(x['rule'] || {}, d) }
          next unless c

          ids[i] = c['id']
          claimed << c['id']
        end
        # Reuse leftover rules for changed bodies (update in place) before creating new ones.
        leftovers = current.reject { |c| claimed.include?(c['id']) }
        desired.each_with_index do |d, i|
          next if ids[i] || leftovers.empty?

          c = leftovers.shift
          client.update_firewall_rule(c['id'], d)
          ids[i] = c['id']
          claimed << c['id']
        end
        leftovers.each do |c|
          client.delete_firewall_rule(c['id'])
        rescue APIError => e
          raise unless e.not_found?
        end
        order = current.map { |c| c['id'] }.select { |id| claimed.include?(id) }
        # New rules land at position 0, so create bottom-up to keep their relative order.
        (desired.length - 1).downto(0) do |i|
          next if ids[i]

          created = client.create_firewall_rule(ruleset_id, desired[i])
          if created.nil? || created['id'].to_s.empty?
            created = client.list_firewall_rules(ruleset_id).find do |r|
              !claimed.include?(r['id']) && same_rule?(r['rule'] || {}, desired[i])
            end
            raise UsageError, "the API did not return the created firewall rule #{i}" unless created
          end
          ids[i] = created['id']
          claimed << ids[i]
          order.unshift(ids[i])
        end
        ids.each_with_index do |rid, i|
          next if order[i] == rid

          client.move_firewall_rule(rid, order[i])
          order.delete(rid)
          order.insert(i, rid)
        end
        final = client.list_firewall_rules(ruleset_id)
        if final.map { |r| r['id'] } != ids
          raise UsageError, "the ruleset's rules changed while they were being written (another tool or " \
                            'user edited it); run Puppet again'
        end
        final
      end
    end
  end
end
