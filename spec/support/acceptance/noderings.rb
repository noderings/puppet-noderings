# frozen_string_literal: true

require 'securerandom'
require_relative '../../../lib/puppet_x/noderings/compute'
require_relative '../../../lib/puppet_x/noderings/dns'

# The acceptance tests call the real NodeRings API from the system under test.
# They run only with NODERINGS_TOKEN set; the VM examples also need
# NODERINGS_TEST_BILLED=1 because they order a billed server.
module NoderingsAcceptance
  module_function

  def token
    %w[NODERINGS_TOKEN NODERINGS_API_TOKEN NR_API_TOKEN].map { |v| ENV.fetch(v, nil) }.find { |v| !v.to_s.empty? }
  end

  def billed?
    ENV['NODERINGS_TEST_BILLED'] == '1'
  end

  # Names every test object; concurrent runs need different IDs.
  def test_id
    @test_id ||= ENV.fetch('NODERINGS_TEST_ID') { "beaker-#{SecureRandom.hex(3)}" }
  end

  def domain
    ENV.fetch('NODERINGS_TEST_DOMAIN', 'example.com')
  end

  def offer
    {
      plan: ENV.fetch('NODERINGS_TEST_PLAN_CODE', 'SC-GC-1C-1G-20'),
      country: ENV.fetch('NODERINGS_TEST_COUNTRY', 'United States'),
      city: ENV.fetch('NODERINGS_TEST_CITY', 'Ashburn'),
    }
  end

  # A client on the machine running the tests, to check the results.
  def client
    @client ||= PuppetX::Noderings::Client.new(token: token, api_url: ENV.fetch('NODERINGS_API_URL', nil),
                                               user_agent: 'puppet-noderings-acceptance')
  end

  # An OpenSSH public key for a throwaway RSA key (NodeRings stores each key once).
  def public_key
    @public_key ||= begin
      require 'openssl'
      require 'base64'
      rsa = OpenSSL::PKey::RSA.generate(2048)
      str = ->(v) { [v.bytesize].pack('N') + v }
      mpint = ->(b) { str.call((b.getbyte(0) & 0x80 == 0) ? b : "\0#{b}") }
      "ssh-rsa #{Base64.strict_encode64(str.call('ssh-rsa') + mpint.call(rsa.e.to_s(2)) + mpint.call(rsa.n.to_s(2)))} #{test_id}"
    end
  end
end
