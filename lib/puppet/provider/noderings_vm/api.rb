# frozen_string_literal: true

require_relative '../noderings'

Puppet::Type.type(:noderings_vm).provide(:api, parent: Puppet::Provider::Noderings) do
  desc 'Manages virtual machines through the NodeRings API.'

  mk_resource_methods

  def self.compute
    PuppetX::Noderings::Compute
  end

  def self.vm_hash(machine, ruleset_names)
    view = compute.view(machine)
    {
      name: machine['hostname'],
      ensure: :present,
      id: machine['id'],
      ipv4: view['ipv4'],
      ipv6: view['ipv6'],
      plan_code: view['plan_code'],
      distro: view['distro'],
      tags: view['tags'],
      power_state: view['power_state'].to_sym,
      firewall_ruleset_id: view['firewall_ruleset_id'].to_s,
      firewall_ruleset: ruleset_names.fetch(view['firewall_ruleset_id'].to_s, view['firewall_ruleset_id'].to_s),
    }
  end

  def self.ruleset_names(client)
    api('listing firewall rulesets') { client.list_firewall_rulesets }.to_h { |r| [r['id'], r['name']] }
  end

  def self.instances(client = nil)
    client ||= api('connecting') { PuppetX::Noderings::Config.client }
    names = ruleset_names(client)
    api('listing virtual machines') { client.list_virtual_machines }.map { |vm| new(vm_hash(vm, names)) }
  end

  def self.prefetch(resources)
    client = api('connecting') { prefetch_client(resources) }
    names = ruleset_names(client)
    vms = api('listing virtual machines') { client.list_virtual_machines }
    resources.each do |hostname, res|
      matches = vms.select { |v| v['hostname'] == hostname }
      if matches.length > 1
        raise Puppet::Error, "#{matches.length} NodeRings virtual machines are named #{hostname} " \
                             "(#{matches.map { |v| v['id'] }.join(', ')}); delete the extra ones or rename them"
      end
      res.provider = new(vm_hash(matches.first, names)) if matches.first
    end
  end

  def compute
    self.class.compute
  end

  def timeout
    resource[:wait_timeout] || PuppetX::Noderings::DEFAULT_WAIT_TIMEOUT
  end

  def ssh_key_ids
    api('resolving SSH keys') { compute.resolve_ssh_keys(client, Array(resource[:ssh_keys])) }
  end

  def password
    PuppetX::Noderings::Config.unwrap(resource[:password])
  end

  def ruleset_id(name)
    api('resolving the firewall ruleset') { compute.resolve_ruleset(client, name) }
  end

  def offer
    return [resource[:plan_id], resource[:region_id]] if resource[:plan_id] && resource[:region_id]

    unless resource[:plan] && resource[:country] && resource[:city]
      raise Puppet::Error, "noderings_vm[#{resource[:name]}] does not exist; to order it give plan, country and city " \
                           '(or plan_id and region_id)'
    end
    plan_id, region_id, = api('finding an offer') do
      compute.choose_offer(client, resource[:plan], resource[:country], resource[:city],
                           billing_type: resource[:billing_type].to_s, provider_id: resource[:provider_id],
                           sort: resource[:sort].to_s, provider: resource[:hosting_provider])
    end
    [plan_id, region_id]
  end

  def create
    plan_id, region_id = offer
    keys = ssh_key_ids
    raise Puppet::Error, "noderings_vm[#{resource[:name]}]: a new VM needs ssh_keys or a password so you can log in" if keys.empty? && password.to_s.empty?

    rs = resource[:firewall_ruleset].to_s.empty? ? nil : ruleset_id(resource[:firewall_ruleset])
    vm = api("ordering virtual machine #{resource[:name]}") do
      compute.order_vm(client, resource[:name], plan_id, region_id,
                       distro: resource[:distro] || 'ubuntu_24_04', ssh_key_ids: keys, password: password,
                       tags: Array(resource[:tags]), ruleset_id: rs, wait: true, timeout: timeout)
    end
    @property_hash = self.class.vm_hash(vm, rs ? { rs => resource[:firewall_ruleset] } : {})
    self.power_state = :stopped if resource[:power_state] == :stopped
  end

  def destroy
    id = @property_hash[:id]
    api("deleting virtual machine #{resource[:name]}") do
      compute.waiter(client, timeout).retry_busy do
        client.delete_virtual_machine(id)
      rescue PuppetX::Noderings::APIError => e
        raise unless e.not_found?
      end
    end
    @property_hash.clear
  end

  def distro=(value)
    unless resource[:allow_reinstall] == :true
      raise Puppet::Error, "NodeRings virtual machine #{resource[:name]} runs #{@property_hash[:distro]}, not #{value}. " \
                           'Reinstalling erases its disk, so it is only done with allow_reinstall => true'
    end
    keys = ssh_key_ids
    vm = api("reinstalling virtual machine #{resource[:name]}") do
      compute.reinstall(client, @property_hash[:id], resource[:name], value, ssh_key_ids: keys, password: password, timeout: timeout)
    end
    @property_hash[:distro] = PuppetX::Noderings.trim_enum(vm['distro'], 'DISTRO_')
  end

  def tags=(value)
    have = Array(@property_hash[:tags])
    want = Array(value).uniq.sort
    api("updating the tags of #{resource[:name]}") do
      client.update_virtual_machine_tags(@property_hash[:id], add: want - have, remove: have - want)
    end
    @property_hash[:tags] = want
  end

  def firewall_insync?(is, should)
    return @property_hash[:firewall_ruleset_id].to_s.empty? if should.to_s.empty?

    [is.to_s, @property_hash[:firewall_ruleset_id].to_s].include?(should.to_s)
  end

  def firewall_ruleset=(value)
    if value.to_s.empty?
      api("detaching the firewall from #{resource[:name]}") do
        compute.detach_firewall(client, @property_hash[:id], @property_hash[:firewall_ruleset_id], timeout: timeout)
      end
      @property_hash[:firewall_ruleset_id] = ''
    else
      id = ruleset_id(value)
      api("attaching firewall ruleset #{value} to #{resource[:name]}") do
        compute.attach_firewall(client, @property_hash[:id], id, timeout: timeout)
      end
      @property_hash[:firewall_ruleset_id] = id
    end
    @property_hash[:firewall_ruleset] = value
  end

  def power_state=(value)
    vm = api("changing the power of #{resource[:name]}") do
      compute.set_power(client, @property_hash[:id], value.to_s, timeout: timeout)
    end
    @property_hash[:power_state] = compute.power_state(vm).to_sym
  end
end
