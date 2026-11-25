# frozen_string_literal: true

#
# Copyright:: NodeRings
# License:: Apache-2.0
#

require_relative '../../puppet_x/noderings/config'
require_relative '../../puppet_x/noderings/compute'
require_relative '../../puppet_x/noderings/dns'
require_relative '../../puppet_x/noderings/firewall'

# Base class for the providers that talk to the NodeRings API.
class Puppet::Provider::Noderings < Puppet::Provider
  API_ERRORS = [PuppetX::Noderings::APIError, PuppetX::Noderings::UsageError, PuppetX::Noderings::WaitTimeout].freeze

  # Runs an API call and turns its failure into a Puppet::Error.
  def self.api(what)
    yield
  rescue *API_ERRORS, *PuppetX::Noderings::CONNECTION_ERRORS => e
    raise Puppet::Error, "NodeRings: #{what}: #{e.message}"
  end

  def api(what, &block)
    self.class.api(what, &block)
  end

  # The client for prefetching: credentials from the first resource that has
  # its own, else from the environment or noderings.yaml.
  def self.prefetch_client(resources)
    with_token = resources.values.find { |r| !r[:api_token].nil? }
    PuppetX::Noderings::Config.client(with_token)
  end

  def client
    PuppetX::Noderings::Config.client(resource)
  end

  def exists?
    @property_hash[:ensure] == :present
  end
end
