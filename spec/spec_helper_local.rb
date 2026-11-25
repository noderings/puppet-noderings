# frozen_string_literal: true

require_relative 'support/fake_noderings'
require_relative 'support/apply_helper'
require_relative '../lib/puppet_x/noderings/config'

# Every example talks to an in-memory NodeRings API with a test token.
RSpec.shared_context 'with a fake NodeRings API' do
  let(:fake) { FakeNodeRings.new }

  before do
    PuppetX::Noderings::Config.transport = fake
    PuppetX::Noderings::Config.sleeper = ->(_s) {}
    PuppetX::Noderings::Config.reset!
    ENV['NODERINGS_TOKEN'] = 'test-token'
  end

  after do
    ENV.delete('NODERINGS_TOKEN')
    PuppetX::Noderings::Config.reset!
  end
end

RSpec.configure { |c| c.include_context 'with a fake NodeRings API' }
