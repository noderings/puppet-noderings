# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'noderings class' do
  it 'writes the settings file readable only by root' do
    pp = "class { 'noderings': api_token => Sensitive('dummy-token'), config_file => '/tmp/noderings-class-test.yaml' }"
    apply_manifest(pp, catch_failures: true)
    apply_manifest(pp, catch_changes: true)
    expect(file('/tmp/noderings-class-test.yaml')).to be_mode 600
    expect(file('/tmp/noderings-class-test.yaml').content).to include('token: "dummy-token"')
  end
end
