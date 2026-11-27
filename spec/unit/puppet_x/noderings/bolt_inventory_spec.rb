# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'tmpdir'
require_relative '../../../../lib/puppet_x/noderings/bolt_inventory'

describe PuppetX::Noderings::BoltInventory do
  def vm(id, hostname, ipv4, status: 'OPERATION_STATUS_STARTED', tags: [], **extra)
    fake.vms[id] = {
      'id' => id, 'hostname' => hostname, 'ipv4' => ipv4, 'ipv6' => '2001:db8::1',
      'operationStatus' => status, 'tags' => tags, 'distro' => 'DISTRO_UBUNTU_24_04',
      'planCode' => 'SC-1C-1G', 'planId' => 'plan', 'regionId' => 'region', 'regionCity' => 'Ashburn',
      'regionCountry' => 'United States', 'providerName' => 'Acme', 'planBillingType' => 'BILLING_TYPE_USAGE',
      'cpu' => 1, 'memory' => '1024', 'storage' => 20_480, 'instantAppSlug' => '',
    }.merge(extra)
  end

  def resolve(params = {}, env = { 'NODERINGS_TOKEN' => 'test-token' })
    described_class.resolve(params, env: env, transport: fake, sleeper: ->(_s) {})
  end

  before do
    vm('b', 'web-2', '203.0.113.2', tags: %w[web prod])
    vm('a', 'web-1', '203.0.113.1', tags: %w[web puppet-create-abc])
    vm('c', 'db-1', '203.0.113.3', status: 'OPERATION_STATUS_STOPPED', tags: ['db'])
    vm('d', 'new-1', '', status: 'OPERATION_STATUS_PROVISIONING')
  end

  it 'lists running VMs as targets named by hostname, sorted, with facts' do
    targets = resolve
    expect(targets.map { |t| [t['name'], t['uri']] }).to eq [%w[web-1 203.0.113.1], %w[web-2 203.0.113.2]]
    facts = targets.first['facts']['noderings']
    expect(facts).to include(
      'id' => 'a', 'power_state' => 'running', 'distro' => 'ubuntu_24_04', 'region_city' => 'Ashburn',
      'provider_name' => 'Acme', 'cpus' => 1, 'memory_mb' => 1024, 'disk_mb' => 20_480, 'instant_app' => nil
    )
    expect(facts['tags']).to eq ['web'] # the provider's internal create tag is hidden
  end

  it 'filters by tags, power state and hostname' do
    expect(resolve('tags' => %w[web prod]).map { |t| t['name'] }).to eq ['web-2']
    expect(resolve('power_states' => ['stopped']).map { |t| t['name'] }).to eq ['db-1']
    expect(resolve('power_states' => ['all']).map { |t| t['name'] }).to eq %w[db-1 new-1 web-1 web-2]
    expect(resolve('name_pattern' => '^web-[2-9]$').map { |t| t['name'] }).to eq ['web-2']
  end

  it 'maps fields, including nested config, facts and vars' do
    targets = resolve(
      'tags' => ['prod'],
      'target_mapping' => {
        'name' => 'id', 'uri' => 'ipv6', 'alias' => 'hostname',
        'config' => { 'ssh' => { 'host' => 'ipv4' } },
        'vars' => { 'plan' => 'plan_code', 'first_tag' => 'tags.0', 'missing' => 'nope' },
        'facts' => { 'city' => 'region_city' },
      },
    )
    expect(targets).to eq [{
      'name' => 'b', 'uri' => '2001:db8::1', 'alias' => 'web-2',
      'config' => { 'ssh' => { 'host' => '203.0.113.2' } },
      'vars' => { 'plan' => 'SC-1C-1G', 'first_tag' => 'prod' },
      'facts' => { 'noderings' => targets.first['facts']['noderings'], 'city' => 'Ashburn' },
    }]
  end

  it 'leaves out VMs without an address, and names by uri when the name is empty' do
    targets = resolve('power_states' => ['all'], 'target_mapping' => { 'name' => 'instant_app' })
    expect(targets.map { |t| t['name'] }).to eq %w[203.0.113.1 203.0.113.2 203.0.113.3]
  end

  it 'uses the token, API URL and organization from params before the environment' do
    resolve({ 'token' => 'param-token', 'organization_id' => 'org-1' }, {})
    call = fake.calls.last
    expect(call.inspect).to include('param-token').and include('org-1')
  end

  it 'explains a missing token and bad options' do
    expect { resolve({}, {}) }.to raise_error(PuppetX::Noderings::UsageError, %r{NODERINGS_TOKEN})
    expect { resolve('target_mapping' => { 'host' => 'ipv4' }) }.to raise_error(PuppetX::Noderings::UsageError, %r{unknown keys: host})
    expect { resolve('target_mapping' => { 'vars' => 'plan_code' }) }.to raise_error(PuppetX::Noderings::UsageError, %r{vars})
    expect { resolve('name_pattern' => '(') }.to raise_error(PuppetX::Noderings::UsageError, %r{regular expression})
  end

  describe 'the resolve_reference task' do
    let(:root) { File.expand_path('../../../..', __dir__) }

    it 'loads its files from the Bolt install dir and reports errors the Bolt way' do
      Dir.mktmpdir do |dir|
        File.symlink(root, File.join(dir, 'noderings'))
        env = ENV.to_h.reject { |k, _| PuppetX::Noderings::TOKEN_ENV_VARS.include?(k) }
        out, status = Open3.capture2(env, 'ruby', File.join(root, 'tasks/resolve_reference.rb'),
                                     stdin_data: { _installdir: dir }.to_json, unsetenv_others: true)
        expect(status.exitstatus).to eq 1
        expect(JSON.parse(out)['_error']).to include('kind' => 'noderings/inventory-error', 'msg' => %r{No NodeRings API token})
      end
    end

    it 'has metadata that lists every file it loads' do
      meta = JSON.parse(File.read(File.join(root, 'tasks/resolve_reference.json')))
      files = meta['files'].map { |f| f.delete_prefix('noderings/') }
      expect(files).to all(satisfy { |f| File.exist?(File.join(root, f)) })
      expect(files).to include('lib/puppet_x/noderings/bolt_inventory.rb', 'lib/puppet_x/noderings/client.rb', 'lib/puppet_x/noderings/compute.rb')
      expect(meta['parameters']['token']['sensitive']).to be true
    end
  end
end
