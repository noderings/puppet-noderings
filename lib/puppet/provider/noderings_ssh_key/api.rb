# frozen_string_literal: true

require_relative '../noderings'

Puppet::Type.type(:noderings_ssh_key).provide(:api, parent: Puppet::Provider::Noderings) do
  desc 'Manages SSH keys through the NodeRings API.'

  mk_resource_methods

  def self.instances(client = nil)
    client ||= api('connecting') { PuppetX::Noderings::Config.client }
    api('listing SSH keys') { client.list_ssh_keys }.map do |key|
      new(name: key['name'], ensure: :present, public_key: key['publicKey'], id: key['id'])
    end
  end

  def self.prefetch(resources)
    client = api('connecting') { prefetch_client(resources) }
    instances(client).each do |prov|
      resources[prov.name].provider = prov if resources[prov.name]
    end
  end

  def create
    raise Puppet::Error, "noderings_ssh_key[#{resource[:name]}]: public_key is required to create the key" if resource[:public_key].to_s.empty?

    key = api("creating SSH key #{resource[:name]}") do
      client.create_ssh_key(resource[:name], resource[:public_key])
    rescue PuppetX::Noderings::APIError => e
      raise unless e.code == PuppetX::Noderings::CODE_ALREADY_EXISTS

      raise PuppetX::Noderings::UsageError, 'this public key is already stored in NodeRings under another name; ' \
                                            'NodeRings keeps each key once, so use that name or delete it first'
    end
    @property_hash = { name: resource[:name], ensure: :present, public_key: resource[:public_key], id: key && key['id'] }
  end

  def destroy
    api("deleting SSH key #{resource[:name]}") do
      client.delete_ssh_key(@property_hash[:id])
    rescue PuppetX::Noderings::APIError => e
      raise unless e.not_found?
    end
    @property_hash.clear
  end

  # NodeRings cannot change a stored key, so a new key replaces the old one.
  def public_key=(_value)
    destroy
    create
  end
end
