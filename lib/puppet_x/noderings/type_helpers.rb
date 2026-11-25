# frozen_string_literal: true

#
# Copyright:: NodeRings
# License:: Apache-2.0
#
# Parameters and behaviour shared by every noderings_* type.

require_relative 'config'

module PuppetX
  module Noderings
    module TypeHelpers
      # A DNS record title of the form zone/record_name/TYPE, as `puppet resource` prints it.
      RECORD_TITLE = %r{\A([^/\s]+)/([^/\s]+)/([A-Za-z0-9]+)\z}.freeze

      module_function

      # Adds the API connection parameters and the autorequire of noderings.yaml.
      def add_api_params(type)
        type.newparam(:api_token) do
          desc <<~DESC
            NodeRings API token. Defaults to the NODERINGS_TOKEN environment variable, then
            the token the `noderings` class wrote to noderings.yaml. Pass it as Sensitive.
          DESC
          sensitive true
        end

        type.newparam(:api_url) do
          desc 'NodeRings API endpoint. Defaults to NODERINGS_API_URL, then noderings.yaml, then https://api.noderings.com.'
        end

        type.newparam(:organization_id) do
          desc 'Organization to act in, for tokens that can reach more than one.'
        end

        type.autorequire(:file) { [PuppetX::Noderings::Config.path] }
      end

      # A property whose value only the provider sets (shown by `puppet resource`).
      def add_read_only(type, name, description)
        type.newproperty(name) do
          desc "#{description} Read-only."
          validate { |_v| raise ArgumentError, "#{name} is read-only" }
        end
      end
    end
  end
end
