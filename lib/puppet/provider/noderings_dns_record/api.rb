# frozen_string_literal: true

require_relative '../noderings'

Puppet::Type.type(:noderings_dns_record).provide(:api, parent: Puppet::Provider::Noderings) do
  desc 'Manages DNS record sets through the NodeRings API.'

  mk_resource_methods

  def self.dns
    PuppetX::Noderings::DNS
  end

  def self.record_hash(zone, rec)
    type = rec['type'].to_s.upcase
    rel = dns.relative_name(rec['name'], '')
    {
      name: "#{dns.normalize_zone_name(zone['name'])}/#{rel}/#{type}",
      ensure: :present,
      zone: dns.normalize_zone_name(zone['name']),
      zone_id: zone['id'],
      record_name: rel,
      type: type,
      values: Array(rec['rdata']).map { |v| dns.from_api(type, v) },
      ttl: rec['ttl'].to_i,
    }
  end

  def self.zone_records(client, zone)
    api("listing records of #{zone['name']}") { client.list_dns_records(zone['id']) }.reject { |r| r['system'] }
  end

  def self.instances(client = nil)
    client ||= api('connecting') { PuppetX::Noderings::Config.client }
    api('listing DNS zones') { client.list_dns_zones }.flat_map do |zone|
      zone_records(client, zone).map { |rec| new(record_hash(zone, rec)) }
    end
  end

  # Matches each resource to its record set by zone, relative name and type,
  # reading only the zones the catalog uses.
  def self.prefetch(resources)
    client = api('connecting') { prefetch_client(resources) }
    zones = api('listing DNS zones') { client.list_dns_zones }
    cache = {}
    resources.each_value do |res|
      zone = zones.find { |z| z['id'] == res[:zone] || dns.normalize_zone_name(z['name']) == res[:zone] }
      next unless zone

      rel = dns.relative_name(res[:record_name], zone['name'])
      cache[zone['id']] ||= zone_records(client, zone)
      rec = cache[zone['id']].find { |r| dns.relative_name(r['name'], '') == rel && r['type'].to_s.upcase == res[:type] }
      res.provider = new(rec ? record_hash(zone, rec) : { ensure: :absent, zone_id: zone['id'] })
    end
  end

  def zone_id
    id = @property_hash[:zone_id]
    return id if id

    zone = api('listing DNS zones') do
      client.list_dns_zones.find { |z| z['id'] == resource[:zone] || self.class.dns.normalize_zone_name(z['name']) == resource[:zone] }
    end
    raise Puppet::Error, "NodeRings DNS zone #{resource[:zone]} does not exist; declare it with noderings_dns_zone" unless zone

    @property_hash[:zone_id] = zone['id']
  end

  def relative
    @relative ||= self.class.dns.relative_name(resource[:record_name], resource[:zone])
  end

  def write
    type = resource[:type]
    values = Array(resource[:values])
    api("writing DNS record #{relative} #{type} in #{resource[:zone]}") do
      client.upsert_dns_record(zone_id, 'name' => relative, 'type' => type, 'ttl' => resource[:ttl].to_i,
                                        'rdata' => values.map { |v| self.class.dns.to_api(type, v) })
    end
    @property_hash.merge!(ensure: :present, values: values, ttl: resource[:ttl].to_i)
  end

  def create
    raise Puppet::Error, "noderings_dns_record[#{resource[:name]}]: values is required to create the record set" if Array(resource[:values]).empty?

    write
  end

  def destroy
    api("deleting DNS record #{relative} #{resource[:type]} in #{resource[:zone]}") do
      client.delete_dns_record(zone_id, relative, resource[:type])
    rescue PuppetX::Noderings::APIError => e
      raise unless e.not_found?
    end
    @property_hash[:ensure] = :absent
  end

  def values=(_value)
    @dirty = true
  end

  def ttl=(_value)
    @dirty = true
  end

  # Values and TTL are written together, once.
  def flush
    write if @dirty
    @dirty = false
  end
end
