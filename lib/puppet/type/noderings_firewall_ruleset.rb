# frozen_string_literal: true

require_relative '../../puppet_x/noderings/type_helpers'

Puppet::Type.newtype(:noderings_firewall_ruleset) do
  desc <<~DESC
    Manages a NodeRings firewall ruleset and its ordered rules. The ruleset holds
    exactly the rules given, in order; rules that are not listed are removed.

    Each rule is a hash with `direction` (ingress or egress), `action` (accept or
    drop), `protocol` (tcp by default), `source` and `destination` (each with
    `cidrs`, `address_groups`, `address_group_ids` or `vm_tags`), and optional
    `source_ports` and `destination_ports` (one port or one range).

    @example Allow SSH from an office and HTTPS from anywhere
      noderings_firewall_ruleset { 'web':
        ensure => present,
        rules  => [
          { 'direction' => 'ingress', 'action' => 'accept', 'protocol' => 'tcp',
            'destination_ports' => '22', 'source' => { 'cidrs' => ['198.51.100.0/24'] } },
          { 'direction' => 'ingress', 'action' => 'accept', 'protocol' => 'tcp',
            'destination_ports' => '443', 'source' => { 'cidrs' => ['0.0.0.0/0'] } },
        ],
      }
  DESC

  ensurable do
    desc 'Whether the ruleset should exist.'
    defaultvalues
    defaultto(:present)
  end

  newparam(:name, namevar: true) do
    desc 'Name of the ruleset.'
  end

  newproperty(:rules, array_matching: :all) do
    desc 'Ordered rules, at most 50. See the type description for the keys.'
    defaultto([])
    munge { |v| PuppetX::Noderings::Firewall.stringify(v) }
    validate do |v|
      raise ArgumentError, 'each rule must be a hash' unless v.is_a?(Hash)
    end

    # Rules compare by meaning: CIDR spelling and list order inside a rule do not matter.
    def insync?(is)
      provider.rules_insync?(is, should)
    end

    def change_to_s(current, wanted)
      "set #{Array(wanted).length} rule(s) (had #{Array(current).length})"
    end
  end

  newparam(:force_delete, boolean: true) do
    desc 'With ensure absent, also delete a ruleset still attached to virtual machines.'
    newvalues(:true, :false)
    defaultto(:false)
  end

  PuppetX::Noderings::TypeHelpers.add_read_only(self, :id, 'The ruleset ID.')
  PuppetX::Noderings::TypeHelpers.add_api_params(self)

  validate do
    rules = Array(self[:rules])
    raise ArgumentError, "a ruleset holds at most #{PuppetX::Noderings::Firewall::MAX_RULES} rules" if rules.length > PuppetX::Noderings::Firewall::MAX_RULES

    rules.each_with_index do |rule, i|
      error = PuppetX::Noderings::Firewall.validate_rule(rule, i)
      raise ArgumentError, error if error
    end
  end
end
