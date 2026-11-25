# frozen_string_literal: true

require_relative '../noderings'

Puppet::Type.type(:noderings_dns_zone).provide(:api, parent: Puppet::Provider::Noderings) do
  desc 'Manages DNS zones through the NodeRings API.'

  mk_resource_methods

  def self.signed?(mode)
    !['', 'unsigned'].include?(PuppetX::Noderings.trim_enum(mode, 'DNSSEC_MODE_'))
  end

  def self.zone_hash(client, zone)
    # The zone list omits the nameservers, so read each zone.
    full = api("reading DNS zone #{zone['name']}") { client.get_dns_zone(zone['id']) } || zone
    sec = api("reading DNSSEC of #{zone['name']}") { client.get_dnssec(zone['id']) }
    {
      name: PuppetX::Noderings::DNS.normalize_zone_name(full['name']),
      ensure: :present,
      id: full['id'],
      dnssec: signed?(sec['mode']) ? :true : :false,
      nameservers: Array(full['assignedNameservers']),
      ds_record: sec['ds'].to_s.empty? ? nil : sec['ds'],
    }
  end

  def self.instances(client = nil, wanted = nil)
    client ||= api('connecting') { PuppetX::Noderings::Config.client }
    zones = api('listing DNS zones') { client.list_dns_zones }
    zones = zones.select { |z| wanted.include?(PuppetX::Noderings::DNS.normalize_zone_name(z['name'])) } if wanted
    zones.map { |z| new(zone_hash(client, z)) }
  end

  def self.prefetch(resources)
    client = api('connecting') { prefetch_client(resources) }
    instances(client, resources.keys).each do |prov|
      resources[prov.name].provider = prov if resources[prov.name]
    end
  end

  def create
    zone = api("creating DNS zone #{resource[:name]}") { client.create_dns_zone(resource[:name]) }
    @property_hash = { name: resource[:name], ensure: :present, id: zone['id'], dnssec: :false }
    self.dnssec = :true if resource[:dnssec] == :true
  end

  def destroy
    api("deleting DNS zone #{resource[:name]}") do
      client.delete_dns_zone(@property_hash[:id], force: resource[:force_delete] == :true)
    rescue PuppetX::Noderings::APIError => e
      raise unless e.not_found?
    end
    @property_hash.clear
  end

  def dnssec=(value)
    if value == :true
      api("signing DNS zone #{resource[:name]}") { client.enable_dnssec(@property_hash[:id]) }
    else
      api("removing DNSSEC from #{resource[:name]}") { client.disable_dnssec(@property_hash[:id]) }
    end
    @property_hash[:dnssec] = value
  end
end
