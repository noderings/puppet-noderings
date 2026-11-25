# frozen_string_literal: true

require 'spec_helper'

describe 'noderings types' do
  def type(name, params)
    Puppet::Type.type(name).new(params)
  end

  describe Puppet::Type.type(:noderings_ssh_key) do
    it 'rejects text that is not a public key' do
      expect { type(:noderings_ssh_key, name: 'k', public_key: 'nope') }.to raise_error(Puppet::ResourceError, %r{must look like})
    end

    it 'ignores the key comment when comparing' do
      key = type(:noderings_ssh_key, name: 'k', public_key: 'ssh-ed25519 AAAA laptop')
      expect(key.property(:public_key).insync?('ssh-ed25519 AAAA other')).to be true
      expect(key.property(:public_key).insync?('ssh-ed25519 BBBB laptop')).to be false
    end

    it 'treats the token as sensitive' do
      key = type(:noderings_ssh_key, name: 'k', public_key: 'ssh-ed25519 AAAA', api_token: 'secret')
      expect(key.parameter(:api_token).sensitive).to be true
    end
  end

  describe Puppet::Type.type(:noderings_dns_zone) do
    it 'normalizes the name' do
      expect(type(:noderings_dns_zone, name: 'Example.COM.')[:name]).to eq 'example.com'
    end

    it 'rejects names that are not domains' do
      expect { type(:noderings_dns_zone, name: 'localhost') }.to raise_error(Puppet::ResourceError, %r{not a domain name})
    end

    it 'does not let nameservers be set' do
      expect { type(:noderings_dns_zone, name: 'example.com', nameservers: ['a.']) }.to raise_error(Puppet::ResourceError, %r{read-only})
    end
  end

  describe Puppet::Type.type(:noderings_dns_record) do
    let(:base) { { name: 'www A', zone: 'Example.com', record_name: 'www', type: 'a', values: ['192.0.2.1'] } }

    it 'normalizes zone and type, and defaults ttl' do
      rec = type(:noderings_dns_record, base)
      expect([rec[:zone], rec[:type], rec[:ttl]]).to eq ['example.com', 'A', 3600]
    end

    it 'reads zone, name and type from a zone/name/TYPE title, as puppet resource lists them' do
      rec = type(:noderings_dns_record, name: 'example.com/@/MX', values: ['10 mx.example.net.'])
      expect([rec[:zone], rec[:record_name], rec[:type]]).to eq ['example.com', '@', 'MX']
    end

    it 'defaults record_name to the title' do
      expect(type(:noderings_dns_record, base.merge(name: 'mail', record_name: nil).compact)[:record_name]).to eq 'mail'
    end

    it 'validates values by type' do
      expect { type(:noderings_dns_record, base.merge(values: ['2001:db8::1'])) }.to raise_error(Puppet::ResourceError, %r{not an IPv4 address})
      expect { type(:noderings_dns_record, base.merge(type: 'CNAME', values: %w[a. b.])) }.to raise_error(Puppet::ResourceError, %r{exactly one})
    end

    it 'rejects unknown types and bad TTLs' do
      expect { type(:noderings_dns_record, base.merge(type: 'XYZ')) }.to raise_error(Puppet::ResourceError, %r{type must be one of})
      expect { type(:noderings_dns_record, base.merge(ttl: 5)) }.to raise_error(Puppet::ResourceError, %r{between 30 and 86400})
    end

    it 'compares values the way the API stores them' do
      rec = type(:noderings_dns_record, base.merge(type: 'CNAME', values: ['www.example.net']))
      expect(rec.property(:values).insync?(['WWW.example.net.'])).to be true
    end

    it 'requires its zone' do
      catalog = Puppet::Resource::Catalog.new
      rec = type(:noderings_dns_record, base)
      zone = type(:noderings_dns_zone, name: 'example.com')
      [rec, zone].each { |r| catalog.add_resource(r) }
      expect(rec.autorequire.map { |e| e.source.ref }).to eq ['Noderings_dns_zone[example.com]']
      expect { type(:noderings_dns_record, base.merge(zone: nil).compact) }.to raise_error(Puppet::ResourceError, %r{zone is required})
    end
  end

  describe Puppet::Type.type(:noderings_firewall_ruleset) do
    let(:ssh) { { 'direction' => 'ingress', 'action' => 'accept', 'destination_ports' => '22', 'source' => { 'cidrs' => ['0.0.0.0/0'] } } }

    it 'accepts valid rules with symbol or string keys' do
      expect { type(:noderings_firewall_ruleset, name: 'web', rules: [ssh, { direction: 'egress', action: 'drop', protocol: 'any', destination: { cidrs: ['10.0.0.0/8'] } }]) }.not_to raise_error
    end

    it 'explains invalid rules' do
      expect { type(:noderings_firewall_ruleset, name: 'web', rules: [ssh.merge('destination_ports' => '80,443')]) }.to raise_error(Puppet::ResourceError, %r{one port such as 443})
      expect { type(:noderings_firewall_ruleset, name: 'web', rules: [ssh.merge('action' => 'allow')]) }.to raise_error(Puppet::ResourceError, %r{action must be one of accept, drop})
    end
  end

  describe Puppet::Type.type(:noderings_vm) do
    it 'normalizes the distro' do
      expect(type(:noderings_vm, name: 'web-1', distro: 'Ubuntu-24.04')[:distro]).to eq 'ubuntu_24_04'
    end

    it 'rejects invalid hostnames and values' do
      expect { type(:noderings_vm, name: 'web_1!') }.to raise_error(Puppet::ResourceError, %r{not a valid hostname})
      expect { type(:noderings_vm, name: 'web-1', power_state: 'paused') }.to raise_error(Puppet::ResourceError)
      expect { type(:noderings_vm, name: 'web-1', ipv4: '192.0.2.1') }.to raise_error(Puppet::ResourceError, %r{read-only})
    end

    it 'treats the password as sensitive' do
      expect(type(:noderings_vm, name: 'web-1', password: 'pw').parameter(:password).sensitive).to be true
    end

    it 'autorequires its SSH keys and firewall ruleset' do
      catalog = Puppet::Resource::Catalog.new
      vm = type(:noderings_vm, name: 'web-1', ssh_keys: ['laptop'], firewall_ruleset: 'web')
      key = type(:noderings_ssh_key, name: 'laptop', public_key: 'ssh-ed25519 AAAA')
      rs = type(:noderings_firewall_ruleset, name: 'web')
      [vm, key, rs].each { |r| catalog.add_resource(r) }
      expect(vm.autorequire.map { |e| e.source.ref }).to contain_exactly('Noderings_ssh_key[laptop]', 'Noderings_firewall_ruleset[web]')
    end
  end
end
