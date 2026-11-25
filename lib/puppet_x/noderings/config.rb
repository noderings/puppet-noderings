# frozen_string_literal: true

#
# Copyright:: NodeRings
# License:: Apache-2.0
#
# Where the NodeRings types find their API credentials.

require 'json'
require 'yaml'
require_relative 'client'

module PuppetX
  module Noderings
    # Reads credentials and builds API clients for the types.
    module Config
      FILE_NAME = 'noderings.yaml'

      class << self
        # Tests plug an in-memory API in here.
        attr_accessor :transport, :sleeper
      end

      module_function

      # The file the noderings class writes, in the Puppet confdir.
      def path
        File.join(Puppet[:confdir], FILE_NAME)
      end

      # Settings from noderings.yaml, or {} when it does not exist.
      def file_settings
        return {} unless File.exist?(path)

        data = YAML.safe_load(File.read(path)) || {}
        raise Puppet::Error, "#{path} must hold a YAML hash" unless data.is_a?(Hash)

        data.transform_keys(&:to_s)
      end

      def unwrap(value)
        value.respond_to?(:unwrap) ? value.unwrap : value
      end

      # The token, API URL and organization: from the resource, then the
      # environment, then noderings.yaml.
      def settings(resource = nil)
        file = file_settings
        pick = lambda do |param, env_vars, key|
          value = resource && unwrap(resource[param])
          value = env_vars.map { |v| ENV.fetch(v, nil) }.find { |v| !v.to_s.empty? } if value.to_s.empty?
          value = file[key] if value.to_s.empty?
          value.to_s.empty? ? nil : value.to_s
        end
        {
          token: pick.call(:api_token, TOKEN_ENV_VARS, 'token'),
          api_url: pick.call(:api_url, ['NODERINGS_API_URL'], 'api_url'),
          organization_id: pick.call(:organization_id, ['NODERINGS_ORGANIZATION_ID'], 'organization_id'),
        }
      end

      # A client for these settings. Clients are shared by settings, so one
      # Puppet run reuses connections and caches.
      def client(resource = nil)
        s = settings(resource)
        @clients ||= {}
        @clients[s] ||= Client.new(
          token: s[:token], api_url: s[:api_url], organization_id: s[:organization_id],
          user_agent: "puppet-noderings/#{module_version} (Puppet #{Puppet.version})",
          transport: transport, sleeper: sleeper
        )
      end

      def reset!
        @clients = nil
      end

      def module_version
        @module_version ||= begin
          meta = File.expand_path('../../../metadata.json', __dir__)
          File.exist?(meta) ? JSON.parse(File.read(meta))['version'] : 'unknown'
        rescue StandardError
          'unknown'
        end
      end
    end
  end
end
