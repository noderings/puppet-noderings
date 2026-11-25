# frozen_string_literal: true

require 'spec_helper_acceptance'

# The examples build on each other (create, check, change, delete), so they run in order.
describe 'noderings types against the NodeRings API', if: NoderingsAcceptance.token, order: :defined do
  let(:id) { NoderingsAcceptance.test_id }
  let(:zone) { "#{id}.#{NoderingsAcceptance.domain}" }
  let(:api) { NoderingsAcceptance.client }

  # Beaker logs the manifests it applies, so the real token travels as a copied
  # file rather than through the noderings class.
  before(:all) do
    confdir = on(default, '/opt/puppetlabs/bin/puppet config print confdir').stdout.strip
    create_remote_file(default, "#{confdir}/noderings.yaml", "token: #{NoderingsAcceptance.token}\n")
    on(default, "chmod 0600 #{confdir}/noderings.yaml")
  end

  context 'with an SSH key, a signed zone with records, and a firewall ruleset' do
    let(:objects_manifest) do
      <<~PUPPET
        noderings_ssh_key { '#{id}-key':
          public_key => '#{NoderingsAcceptance.public_key}',
        }

        noderings_dns_zone { '#{zone}':
          dnssec => true,
        }

        noderings_dns_record { 'www':
          zone   => '#{zone}',
          type   => 'A',
          values => ['192.0.2.10', '192.0.2.11'],
          ttl    => 300,
        }

        noderings_dns_record { 'mail':
          zone        => '#{zone}',
          record_name => '@',
          type        => 'MX',
          values      => ['10 mx1.example.net.', '20 mx2.example.net.'],
        }

        noderings_dns_record { 'spf':
          zone        => '#{zone}',
          record_name => '@',
          type        => 'TXT',
          values      => ['v=spf1 -all', 'a value with "quotes" and spaces'],
        }

        noderings_dns_record { 'blog':
          zone   => '#{zone}',
          type   => 'CNAME',
          values => ['www.example.net.'],
        }

        noderings_firewall_ruleset { '#{id}-web':
          rules => [
            { 'direction' => 'ingress', 'action' => 'accept', 'protocol' => 'tcp', 'destination_ports' => '22', 'source' => { 'cidrs' => ['0.0.0.0/0'] } },
            { 'direction' => 'ingress', 'action' => 'accept', 'protocol' => 'tcp', 'destination_ports' => '443', 'source' => { 'cidrs' => ['::/0'] } },
            { 'direction' => 'ingress', 'action' => 'accept', 'protocol' => 'icmp', 'source' => { 'cidrs' => ['10.0.0.0/8', '192.168.0.0/16'] } },
          ],
        }
      PUPPET
    end

    it 'applies with no errors' do
      apply_manifest(objects_manifest, catch_failures: true)
    end

    it 'applies a second time without changes' do
      apply_manifest(objects_manifest, catch_changes: true)
    end

    it 'created the objects as declared' do
      expect(api.list_ssh_keys.map { |k| k['name'] }).to include("#{id}-key")
      z = PuppetX::Noderings::DNS.find_zone(api, zone)
      expect(z).not_to be_nil
      expect(api.get_dnssec(z['id'])['mode']).not_to eq 'DNSSEC_MODE_UNSIGNED'
      www = PuppetX::Noderings::DNS.find_record(api, z['id'], 'www', 'A')
      expect([www['rdata'].sort, www['ttl']]).to eq [%w[192.0.2.10 192.0.2.11], 300]
      txt = PuppetX::Noderings::DNS.find_record(api, z['id'], '@', 'TXT')
      expect(txt['rdata']).to include('"a value with \\"quotes\\" and spaces"')
      rs = api.list_firewall_rulesets.find { |r| r['name'] == "#{id}-web" }
      expect(api.list_firewall_rules(rs['id']).map { |r| r['rule']['destinationPorts'].to_s }).to eq ['22', '443', '']
    end

    it 'lists them with puppet resource' do
      out = on(default, '/opt/puppetlabs/bin/puppet resource noderings_dns_zone').stdout
      expect(out).to include("noderings_dns_zone { '#{zone}':")
      expect(out).to match(%r{nameservers\s+=> \[})
      expect(on(default, '/opt/puppetlabs/bin/puppet resource noderings_dns_record').stdout).to include("'#{zone}/www/A'")
    end
  end

  context 'with a billed virtual machine', if: NoderingsAcceptance.billed? do
    let(:vm_manifest) do
      <<~PUPPET
        noderings_vm { '#{id}-vm':
          plan             => '#{NoderingsAcceptance.offer[:plan]}',
          country          => '#{NoderingsAcceptance.offer[:country]}',
          city             => '#{NoderingsAcceptance.offer[:city]}',
          distro           => 'ubuntu_24_04',
          ssh_keys         => ['#{id}-key'],
          tags             => ['beaker', 'puppet'],
          firewall_ruleset => '#{id}-web',
          power_state      => 'running',
        }
      PUPPET
    end

    let(:vm_change_manifest) do
      <<~PUPPET
        noderings_vm { '#{id}-vm':
          tags        => ['beaker'],
          power_state => 'stopped',
        }
      PUPPET
    end

    it 'applies with no errors' do
      apply_manifest(vm_manifest, catch_failures: true)
    end

    it 'applies a second time without changes' do
      apply_manifest(vm_manifest, catch_changes: true)
    end

    it 'runs with its tags and firewall' do
      vm = PuppetX::Noderings::Compute.find_vm(api, "#{id}-vm")
      view = PuppetX::Noderings::Compute.view(vm)
      expect(view).to include('power_state' => 'running', 'distro' => 'ubuntu_24_04', 'tags' => %w[beaker puppet])
      expect(vm['firewallRulesetId']).to eq api.list_firewall_rulesets.find { |r| r['name'] == "#{id}-web" }['id']
      expect(on(default, '/opt/puppetlabs/bin/puppet resource noderings_vm').stdout).to include("noderings_vm { '#{id}-vm':")
    end

    it 'applies the change with no errors' do
      apply_manifest(vm_change_manifest, catch_failures: true)
    end

    it 'applies the change a second time without changes' do
      apply_manifest(vm_change_manifest, catch_changes: true)
    end

    it 'stopped and retagged it' do
      view = PuppetX::Noderings::Compute.view(PuppetX::Noderings::Compute.find_vm(api, "#{id}-vm"))
      expect(view).to include('power_state' => 'stopped', 'tags' => ['beaker'])
    end

    it 'refuses to reinstall without allow_reinstall' do
      pp = <<~PUPPET
        noderings_vm { '#{id}-vm': distro => 'debian_13' }
      PUPPET
      result = apply_manifest(pp, expect_failures: true)
      expect(result.stderr).to include('only done with allow_reinstall')
    end

    it 'deletes it' do
      pp = <<~PUPPET
        noderings_vm { '#{id}-vm': ensure => absent }
      PUPPET
      apply_manifest(pp, catch_failures: true)
      expect(PuppetX::Noderings::Compute.find_vm(api, "#{id}-vm")).to be_nil
    end
  end

  context 'when everything is removed' do
    let(:removal_manifest) do
      <<~PUPPET
        noderings_dns_zone { '#{zone}':
          ensure       => absent,
          force_delete => true,
        }

        noderings_firewall_ruleset { '#{id}-web':
          ensure       => absent,
          force_delete => true,
        }

        noderings_ssh_key { '#{id}-key':
          ensure => absent,
        }
      PUPPET
    end

    it 'applies with no errors' do
      apply_manifest(removal_manifest, catch_failures: true)
    end

    it 'applies a second time without changes' do
      apply_manifest(removal_manifest, catch_changes: true)
    end

    it 'left nothing behind' do
      expect(PuppetX::Noderings::DNS.find_zone(api, zone)).to be_nil
      expect(api.list_firewall_rulesets.map { |r| r['name'] }).not_to include("#{id}-web")
      expect(api.list_ssh_keys.map { |k| k['name'] }).not_to include("#{id}-key")
    end
  end
end
