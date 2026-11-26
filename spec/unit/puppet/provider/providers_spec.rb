# frozen_string_literal: true

require 'spec_helper'

describe 'noderings providers' do
  def post(path, body)
    fake.call('POST', "https://api.noderings.com#{path}", {}, body.to_json, 1)
  end

  describe 'noderings_ssh_key' do
    let(:key) { 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA laptop' }

    it 'creates a key once' do
      report = apply(resource(:noderings_ssh_key, 'laptop', public_key: key))
      expect(failed(report)).to be_empty
      expect(fake.ssh_keys.values.first).to include('name' => 'laptop', 'publicKey' => key)
      report = apply_fresh { [resource(:noderings_ssh_key, 'laptop', public_key: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA other')] }
      expect(changed(report)).to be_empty
    end

    it 'replaces a changed key and deletes keys' do
      post('/v1/ssh-keys', name: 'laptop', publicKey: 'ssh-ed25519 OLD')
      apply(resource(:noderings_ssh_key, 'laptop', public_key: key))
      expect(fake.ssh_keys.values.map { |k| k['publicKey'] }).to eq [key]
      apply_fresh { [resource(:noderings_ssh_key, 'laptop', ensure: 'absent')] }
      expect(fake.ssh_keys).to be_empty
    end

    it 'needs a public key to create a key' do
      report = apply(resource(:noderings_ssh_key, 'laptop'))
      expect(failed(report).join).to include('public_key is required')
      expect(fake.ssh_keys).to be_empty
    end

    it 'lists keys for puppet resource' do
      post('/v1/ssh-keys', name: 'laptop', publicKey: key)
      provider = Puppet::Type.type(:noderings_ssh_key).provider(:api)
      expect(provider.instances.map(&:name)).to eq ['laptop']
    end

    it 'explains a key stored under another name' do
      post('/v1/ssh-keys', name: 'other', publicKey: key)
      report = apply(resource(:noderings_ssh_key, 'laptop', public_key: key))
      expect(failed(report).join).to include('already stored in NodeRings under another name')
    end

    it 'fails clearly without a token' do
      ENV.delete('NODERINGS_TOKEN')
      allow(PuppetX::Noderings::Config).to receive(:path).and_return('/nonexistent/noderings.yaml')
      report = apply(resource(:noderings_ssh_key, 'laptop', public_key: key))
      expect(report.logs.map(&:message).join).to include('token is required')
    end

    it 'reads the token from noderings.yaml' do
      ENV.delete('NODERINGS_TOKEN')
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'noderings.yaml'), "token: file-token\n")
        allow(PuppetX::Noderings::Config).to receive(:path).and_return(File.join(dir, 'noderings.yaml'))
        apply(resource(:noderings_ssh_key, 'laptop', public_key: key))
      end
      expect(fake.calls.last[4]['Authorization']).to eq 'Bearer file-token'
      expect(fake.calls.last[4]['User-Agent']).to start_with('puppet-noderings/')
    end
  end

  describe 'noderings_dns_zone and noderings_dns_record' do
    def records
      zone = fake.zones.keys.first
      fake.records[zone]
    end

    def catalog
      [
        resource(:noderings_dns_zone, 'example.com', dnssec: true),
        resource(:noderings_dns_record, 'www', zone: 'example.com', type: 'A', values: %w[192.0.2.10 192.0.2.11], ttl: 300),
        resource(:noderings_dns_record, 'spf', zone: 'example.com', record_name: '@', type: 'TXT', values: ['v=spf1 -all']),
        resource(:noderings_dns_record, 'blog', zone: 'example.com', type: 'CNAME', values: ['WWW.example.net.']),
      ]
    end

    it 'creates a signed zone and its records, then changes nothing' do
      report = apply(catalog)
      expect(failed(report)).to be_empty
      expect(fake.zones.values.first['dnssecMode']).to eq 'DNSSEC_MODE_SIGNED_DS_PENDING'
      expect(records[%w[www A]]).to eq('ttl' => 300, 'rdata' => %w[192.0.2.10 192.0.2.11])
      expect(records[%w[@ TXT]]['rdata']).to eq ['"v=spf1 -all"']
      fake.calls.clear
      report = apply_fresh { catalog }
      expect(changed(report)).to be_empty
      expect(fake.writes).to be_empty
    end

    it 'updates values and TTL in one write' do
      apply(catalog)
      fake.calls.clear
      apply_fresh { [resource(:noderings_dns_record, 'www', zone: 'example.com', type: 'A', values: ['192.0.2.20'], ttl: 600)] }
      expect(fake.writes).to eq [['PUT', "/v1/dns/zones/#{fake.zones.keys.first}/records"]]
      expect(records[%w[www A]]).to eq('ttl' => 600, 'rdata' => ['192.0.2.20'])
    end

    it 'shows nameservers and records to puppet resource' do
      apply(catalog)
      zone = Puppet::Type.type(:noderings_dns_zone).provider(:api).instances.first
      expect(zone.nameservers).to eq %w[ans1.nrings.io ans2.nrings.io]
      expect(zone.ds_record).to eq '12345 13 2 abcdef'
      names = Puppet::Type.type(:noderings_dns_record).provider(:api).instances.map(&:name)
      expect(names).to contain_exactly('example.com/www/A', 'example.com/@/TXT', 'example.com/blog/CNAME')
      # What `puppet resource` does with each listed record set: build a resource from its title and properties.
      listed = Puppet::Type.type(:noderings_dns_record).provider(:api).instances.find { |p| p.name == 'example.com/@/TXT' }
      res = Puppet::Type.type(:noderings_dns_record).new(name: listed.name, values: listed.values, ttl: listed.ttl)
      expect([res[:zone], res[:record_name], res[:type]]).to eq ['example.com', '@', 'TXT']
    end

    it 'deletes records and the zone' do
      apply(catalog)
      apply_fresh do
        [resource(:noderings_dns_record, 'www', zone: 'example.com', type: 'A', ensure: 'absent'),
         resource(:noderings_dns_zone, 'example.com', ensure: 'absent', force_delete: true),]
      end
      expect(fake.zones).to be_empty
    end

    it 'needs values to create a record set' do
      apply(resource(:noderings_dns_zone, 'example.com'))
      report = apply_fresh { [resource(:noderings_dns_record, 'www', zone: 'example.com', type: 'A')] }
      expect(failed(report).join).to include('values is required')
    end

    it 'lists every type the way puppet resource does' do
      apply(catalog)
      apply_fresh do
        [resource(:noderings_ssh_key, 'laptop', public_key: 'ssh-ed25519 AAAA laptop'),
         resource(:noderings_firewall_ruleset, 'web', rules: []),
         resource(:noderings_vm, 'web-1', plan: 'SC-GC-1C-1G-20', country: 'United States', city: 'Ashburn', password: 'pw'),]
      end
      %i[noderings_ssh_key noderings_dns_zone noderings_dns_record noderings_firewall_ruleset noderings_vm].each do |t|
        # Puppet::Type.instances builds each resource from its name and provider, as `puppet resource` does.
        expect(Puppet::Type.type(t).instances).not_to be_empty
        Puppet::Type.type(t).instances.each { |r| expect(r.to_resource.to_hierayaml).to be_a(String) }
      end
    end

    it 'fails a record in a missing zone' do
      report = apply(resource(:noderings_dns_record, 'www', zone: 'nope.example', type: 'A', values: ['192.0.2.1']))
      expect(failed(report).join).to include('nope.example does not exist')
    end
  end

  describe 'noderings_firewall_ruleset' do
    def rules(*ports)
      ports.map { |p| { 'direction' => 'ingress', 'action' => 'accept', 'destination_ports' => p.to_s, 'source' => { 'cidrs' => ['0.0.0.0/0'] } } }
    end

    def ports
      fake.rules.values.first.map { |r| r['rule']['destinationPorts'] }
    end

    it 'creates, reorders and trims rules, keeping IDs' do
      apply(resource(:noderings_firewall_ruleset, 'web', rules: rules(22, 80, 443)))
      expect(ports).to eq %w[22 80 443]
      ids = fake.rules.values.first.map { |r| r['id'] }
      apply_fresh { [resource(:noderings_firewall_ruleset, 'web', rules: rules(443, 22, 80))] }
      expect(ports).to eq %w[443 22 80]
      expect(fake.rules.values.first.map { |r| r['id'] }).to match_array ids
      apply_fresh { [resource(:noderings_firewall_ruleset, 'web', rules: rules(443))] }
      expect(ports).to eq ['443']
      fake.calls.clear
      report = apply_fresh { [resource(:noderings_firewall_ruleset, 'web', rules: rules(443))] }
      expect(changed(report)).to be_empty
    end

    it 'resolves address groups by name' do
      fake.groups['g1'] = { 'id' => 'G1', 'name' => 'office' }
      apply(resource(:noderings_firewall_ruleset, 'web', rules: [{ 'direction' => 'ingress', 'action' => 'accept', 'source' => { 'address_groups' => ['office'] } }]))
      expect(fake.rules.values.first.first['rule']['source']).to eq('addressGroupIds' => { 'addressGroupIds' => ['g1'] })
    end

    it 'deletes with force' do
      apply(resource(:noderings_firewall_ruleset, 'web', rules: rules(22)))
      apply_fresh { [resource(:noderings_firewall_ruleset, 'web', ensure: 'absent', force_delete: true)] }
      expect(fake.rulesets).to be_empty
    end
  end

  describe 'noderings_vm' do
    before do
      post('/v1/ssh-keys', name: 'laptop', publicKey: 'ssh-ed25519 AAAA laptop')
      post('/v1/firewall/rulesets', ruleset: { name: 'web' })
    end

    let(:offer) { { plan: 'SC-GC-1C-1G-20', country: 'United States', city: 'Ashburn' } }

    def vm
      fake.vms.values.first
    end

    it 'orders the cheapest offer with keys, tags and firewall, then changes nothing' do
      params = offer.merge(distro: 'debian-13', ssh_keys: ['laptop'], tags: %w[web puppet], firewall_ruleset: 'web', power_state: 'running')
      report = apply(resource(:noderings_vm, 'web-1', params))
      expect(failed(report)).to be_empty
      body = fake.created_vm_bodies.last
      expect(body).to include('hostname' => 'web-1', 'planId' => FakeNodeRings::PLAN_ID, 'distro' => 'DISTRO_DEBIAN_13',
                              'sshKeyIds' => [fake.ssh_keys.keys.first], 'tags' => %w[puppet web])
      expect(vm['firewallRulesetId']).to eq fake.rulesets.keys.first
      fake.calls.clear
      report = apply_fresh { [resource(:noderings_vm, 'web-1', params)] }
      expect(changed(report)).to be_empty
      expect(fake.writes).to be_empty
    end

    context 'with hosting_provider' do
      [FakeNodeRings::ACME_ID, 'acme-hosting', 'Acme Hosting', '  acme HOSTING '].each do |provider|
        it "orders from the provider given as #{provider.inspect}" do
          report = apply(resource(:noderings_vm, 'web-1', offer.merge(ssh_keys: ['laptop'], hosting_provider: provider)))
          expect(failed(report)).to be_empty
          expect(fake.created_vm_bodies.last).to include('planId' => FakeNodeRings::ACME_PLAN_ID, 'regionId' => FakeNodeRings::ACME_REGION_ID)
        end
      end

      it 'orders the cheapest offer without one' do
        apply(resource(:noderings_vm, 'web-1', offer.merge(ssh_keys: ['laptop'])))
        expect(fake.created_vm_bodies.last['planId']).to eq FakeNodeRings::PLAN_ID
      end

      it 'fails for an unknown provider' do
        report = apply(resource(:noderings_vm, 'web-1', offer.merge(ssh_keys: ['laptop'], hosting_provider: 'Nobody Hosting')))
        expect(failed(report).join).to include('from provider Nobody Hosting')
        expect(fake.created_vm_bodies).to be_empty
      end

      it 'refuses a provider name two providers share' do
        fake.extra_providers << FakeNodeRings::ACME_OFFER.merge('organizationId' => '66666666-6666-6666-6666-666666666666')
        report = apply(resource(:noderings_vm, 'web-1', offer.merge(ssh_keys: ['laptop'], hosting_provider: 'acme hosting')))
        expect(failed(report).join).to include('more than one provider is named acme hosting')
        expect(fake.created_vm_bodies).to be_empty
      end
    end

    it 'converges tags, firewall and power on an existing VM' do
      apply(resource(:noderings_vm, 'web-1', offer.merge(ssh_keys: ['laptop'], tags: ['old'])))
      apply_fresh { [resource(:noderings_vm, 'web-1', tags: ['new'], firewall_ruleset: 'web', power_state: 'stopped')] }
      expect(vm).to include('tags' => ['new'], 'firewallRulesetId' => fake.rulesets.keys.first, 'operationStatus' => 'OPERATION_STATUS_STOPPED')
      expect(fake.created_vm_bodies.length).to eq 1
      apply_fresh { [resource(:noderings_vm, 'web-1', firewall_ruleset: '')] }
      expect(vm['firewallRulesetId']).to be_nil
    end

    it 'refuses to reinstall without allow_reinstall, and reinstalls with it' do
      apply(resource(:noderings_vm, 'web-1', offer.merge(ssh_keys: ['laptop'])))
      report = apply_fresh { [resource(:noderings_vm, 'web-1', distro: 'debian_13')] }
      expect(failed(report).join).to include('only done with allow_reinstall')
      expect(vm['distro']).to eq 'DISTRO_UBUNTU_24_04'
      apply_fresh { [resource(:noderings_vm, 'web-1', distro: 'debian_13', allow_reinstall: true, ssh_keys: ['laptop'])] }
      expect(vm['distro']).to eq 'DISTRO_DEBIAN_13'
    end

    it 'refuses to order without a way to log in or an offer' do
      report = apply(resource(:noderings_vm, 'web-1', offer))
      expect(failed(report).join).to include('needs ssh_keys or a password')
      report = apply_fresh { [resource(:noderings_vm, 'web-2', ssh_keys: ['laptop'])] }
      expect(failed(report).join).to include('give plan, country and city')
      expect(fake.created_vm_bodies).to be_empty
    end

    it 'deletes the VM' do
      apply(resource(:noderings_vm, 'web-1', offer.merge(password: 'secret')))
      expect(fake.created_vm_bodies.last['password']).to eq 'secret'
      apply_fresh { [resource(:noderings_vm, 'web-1', ensure: 'absent')] }
      expect(fake.vms).to be_empty
    end

    it 'lists VMs for puppet resource with their firewall name' do
      apply(resource(:noderings_vm, 'web-1', offer.merge(ssh_keys: ['laptop'], firewall_ruleset: 'web')))
      listed = Puppet::Type.type(:noderings_vm).provider(:api).instances.first
      expect([listed.name, listed.ipv4, listed.firewall_ruleset, listed.power_state]).to eq ['web-1', '192.0.2.50', 'web', :running]
    end
  end
end
