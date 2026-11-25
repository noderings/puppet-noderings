# frozen_string_literal: true

require_relative '../../puppet_x/noderings/type_helpers'

Puppet::Type.newtype(:noderings_vm) do
  desc <<~DESC
    Manages a NodeRings virtual machine. When no VM has the hostname, Puppet orders
    the cheapest marketplace offer that matches `plan`, `country` and `city` (or the
    exact `plan_id` and `region_id`). For an existing VM it keeps `tags`,
    `firewall_ruleset` and `power_state` as declared. Ordering is billed to the
    organization.

    @example A web server behind a firewall
      noderings_vm { 'web-1':
        ensure           => present,
        plan             => 'SC-GC-1C-1G-20',
        country          => 'United States',
        city             => 'Ashburn',
        distro           => 'ubuntu_24_04',
        ssh_keys         => ['deploy'],
        tags             => ['web', 'production'],
        firewall_ruleset => 'web',
      }

    @example List the organization's VMs with their addresses
      $ puppet resource noderings_vm
  DESC

  ensurable do
    desc 'present orders the VM if it does not exist; absent deletes it.'
    defaultvalues
    defaultto(:present)
  end

  newparam(:name, namevar: true) do
    desc 'Hostname of the VM. It identifies the VM, so keep it unique in the organization.'
    validate do |v|
      raise ArgumentError, "#{v.inspect} is not a valid hostname" unless v.to_s =~ %r{\A[a-zA-Z0-9]([a-zA-Z0-9.-]{0,251}[a-zA-Z0-9])?\z}
    end
  end

  newparam(:plan) do
    desc 'Plan code to order, such as SC-GC-1C-1G-20.'
  end

  newparam(:country) do
    desc 'Country of the offer, such as United States.'
  end

  newparam(:city) do
    desc 'City of the offer, such as Ashburn.'
  end

  newparam(:billing_type) do
    desc 'How the plan is billed: usage (hourly), subscription (monthly) or free.'
    newvalues(:usage, :subscription, :free)
    defaultto(:usage)
  end

  newparam(:sort) do
    desc 'Order the cheapest matching offer (price) or the best rated (rating).'
    newvalues(:price, :rating)
    defaultto(:price)
  end

  newparam(:provider_id) do
    desc 'Only consider offers from this marketplace provider.'
  end

  newparam(:plan_id) do
    desc 'Exact plan ID to order, instead of plan, country and city.'
  end

  newparam(:region_id) do
    desc 'Exact region ID to order, with plan_id.'
  end

  newparam(:ssh_keys, array_matching: :all) do
    desc 'Names or IDs of stored SSH keys (noderings_ssh_key) to install. A new VM needs SSH keys or a password.'
    defaultto([])
  end

  newparam(:password) do
    desc 'Root password for a new VM. Pass it as Sensitive.'
    sensitive true
  end

  newparam(:allow_reinstall, boolean: true) do
    desc 'Reinstall an existing VM whose distro differs. Reinstalling erases the disk.'
    newvalues(:true, :false)
    defaultto(:false)
  end

  newparam(:wait_timeout) do
    desc 'Seconds to wait for each operation to finish.'
    defaultto(900)
    munge(&:to_i)
  end

  newproperty(:distro) do
    desc <<~DESC
      Operating system, such as ubuntu_24_04, debian-13 or rocky_9. Defaults to
      ubuntu_24_04 for new VMs. A different distro on an existing VM fails unless
      allow_reinstall is true, because reinstalling erases the disk.
    DESC
    munge { |v| PuppetX::Noderings::Compute.normalize_distro(v) }
  end

  newproperty(:tags, array_matching: :all) do
    desc 'Tags of the VM. Left unset, tags are not managed.'

    def insync?(is)
      Array(is).sort == Array(should).uniq.sort
    end
  end

  newproperty(:firewall_ruleset) do
    desc 'Name or ID of the firewall ruleset to attach. An empty string detaches it. Left unset, the firewall is not managed.'

    def insync?(is)
      provider.firewall_insync?(is, should)
    end
  end

  newproperty(:power_state) do
    desc 'Keep the VM running or stopped. Left unset, power is not managed.'
    newvalues(:running, :stopped)
  end

  PuppetX::Noderings::TypeHelpers.add_read_only(self, :id, 'The VM ID.')
  PuppetX::Noderings::TypeHelpers.add_read_only(self, :ipv4, 'The public IPv4 address.')
  PuppetX::Noderings::TypeHelpers.add_read_only(self, :ipv6, 'The public IPv6 address.')
  PuppetX::Noderings::TypeHelpers.add_read_only(self, :plan_code, 'The plan the VM runs on.')
  PuppetX::Noderings::TypeHelpers.add_api_params(self)

  autorequire(:noderings_ssh_key) { self[:ssh_keys] }
  autorequire(:noderings_firewall_ruleset) { self[:firewall_ruleset].to_s.empty? ? [] : [self[:firewall_ruleset]] }
end
