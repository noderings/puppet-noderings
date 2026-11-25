# frozen_string_literal: true

require_relative '../../puppet_x/noderings/type_helpers'

Puppet::Type.newtype(:noderings_dns_zone) do
  desc <<~DESC
    Manages a DNS zone hosted on NodeRings, and optionally its DNSSEC signing.
    `puppet resource noderings_dns_zone` shows the nameservers to set at your registrar.

    @example A signed zone
      noderings_dns_zone { 'example.com':
        ensure => present,
        dnssec => true,
      }
  DESC

  ensurable do
    desc 'Whether the zone should exist.'
    defaultvalues
    defaultto(:present)
  end

  newparam(:name, namevar: true) do
    desc 'The domain, such as example.com. Case and a trailing dot are ignored.'
    munge { |v| v.to_s.strip.downcase.chomp('.') }
    validate { |v| raise ArgumentError, "#{v.inspect} is not a domain name" unless v.to_s.strip.chomp('.') =~ %r{\A[a-zA-Z0-9.-]+\.[a-zA-Z0-9-]+\z} }
  end

  newproperty(:dnssec, boolean: true) do
    desc 'true signs the zone with DNSSEC, false removes signing. Left unset, signing is not managed.'
    newvalues(:true, :false)
    munge { |v| (v.to_s == 'true') ? :true : :false }
  end

  newparam(:force_delete, boolean: true) do
    desc 'With ensure absent, also delete a zone that still has records.'
    newvalues(:true, :false)
    defaultto(:false)
  end

  PuppetX::Noderings::TypeHelpers.add_read_only(self, :nameservers, 'The nameservers assigned to the zone.')
  PuppetX::Noderings::TypeHelpers.add_read_only(self, :ds_record, 'The DS record to publish at the registrar for a signed zone.')
  PuppetX::Noderings::TypeHelpers.add_api_params(self)
end
