# frozen_string_literal: true

require_relative '../noderings'

Puppet::Type.type(:noderings_firewall_ruleset).provide(:api, parent: Puppet::Provider::Noderings) do
  desc 'Manages firewall rulesets and their ordered rules through the NodeRings API.'

  mk_resource_methods

  def self.fw
    PuppetX::Noderings::Firewall
  end

  def self.instances(client = nil, wanted = nil)
    client ||= api('connecting') { PuppetX::Noderings::Config.client }
    rulesets = api('listing firewall rulesets') { client.list_firewall_rulesets }
    rulesets = rulesets.select { |r| wanted.include?(r['name']) } if wanted
    rulesets.map do |rs|
      current = api("listing the rules of #{rs['name']}") { client.list_firewall_rules(rs['id']) }
      new(name: rs['name'], ensure: :present, id: rs['id'], rules: current.map { |r| fw.rule_view(r) }, api_rules: current)
    end
  end

  def self.prefetch(resources)
    client = api('connecting') { prefetch_client(resources) }
    instances(client, resources.keys).each do |prov|
      resources[prov.name].provider = prov if resources[prov.name]
    end
  end

  # The desired rules in API form, with address group names resolved.
  def desired_api_rules(rules)
    groups = {}
    api('listing firewall address groups') { client.list_firewall_address_groups }.each { |g| groups[g['name']] = g['id'] } if rules.any? { |r| %w[source destination].any? { |s| Array((r[s] || {})['address_groups']).any? } }
    api('reading firewall rules') { rules.map { |r| self.class.fw.rule_to_api(r, groups) } }
  end

  def rules_insync?(_is, should)
    !self.class.fw.rules_differ?(Array(@property_hash[:api_rules]), desired_api_rules(Array(should)))
  end

  def create
    rs = api("creating firewall ruleset #{resource[:name]}") { client.create_firewall_ruleset(resource[:name]) }
    @property_hash = { name: resource[:name], ensure: :present, id: rs['id'], rules: [], api_rules: [] }
    self.rules = resource[:rules] unless Array(resource[:rules]).empty?
  end

  def destroy
    api("deleting firewall ruleset #{resource[:name]}") do
      client.delete_firewall_ruleset(@property_hash[:id], force: resource[:force_delete] == :true)
    rescue PuppetX::Noderings::APIError => e
      raise unless e.not_found?
    end
    @property_hash.clear
  end

  def rules=(value)
    desired = desired_api_rules(Array(value))
    final = api("writing the rules of firewall ruleset #{resource[:name]}") do
      self.class.fw.reconcile(client, @property_hash[:id], desired)
    end
    @property_hash[:api_rules] = final
    @property_hash[:rules] = final.map { |r| self.class.fw.rule_view(r) }
  end
end
