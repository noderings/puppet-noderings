# frozen_string_literal: true

require 'spec_helper'

describe 'noderings' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      context 'with a token' do
        let(:params) { { api_token: sensitive('secret-token'), organization_id: 'org-1' } }

        it { is_expected.to compile.with_all_deps }

        it 'writes the settings readable only by root, without showing them' do
          is_expected.to contain_file("#{Puppet[:confdir]}/noderings.yaml").with(
            ensure: 'file', owner: 'root', group: '0', mode: '0600', show_diff: false,
          )
        end

        it 'puts the token, URL and organization in the file' do
          content = catalogue.resource('File', "#{Puppet[:confdir]}/noderings.yaml")[:content]
          content = content.unwrap if content.respond_to?(:unwrap)
          expect(YAML.safe_load(content)).to eq('token' => 'secret-token', 'api_url' => 'https://api.noderings.com', 'organization_id' => 'org-1')
        end
      end

      context 'without a token' do
        it { is_expected.to compile.and_raise_error(%r{api_token is required}) }
      end

      context 'with ensure absent' do
        let(:params) { { ensure: 'absent' } }

        it { is_expected.to contain_file("#{Puppet[:confdir]}/noderings.yaml").with_ensure('absent') }
      end

      context 'with a plain-text token' do
        let(:params) { { api_token: 'secret-token' } }

        it { is_expected.to compile.and_raise_error(%r{api_token}) }
      end
    end
  end
end
