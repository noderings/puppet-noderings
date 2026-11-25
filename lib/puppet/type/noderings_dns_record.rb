# frozen_string_literal: true

require_relative '../../puppet_x/noderings/type_helpers'

Puppet::Type.newtype(:noderings_dns_record) do
  desc <<~DESC
    Manages the records of one name and type in a NodeRings DNS zone, as one set:
    the values given replace whatever the set held.

    @example Two A records
      noderings_dns_record { 'www A':
        ensure      => present,
        zone        => 'example.com',
        record_name => 'www',
        type        => 'A',
        values      => ['192.0.2.10', '192.0.2.11'],
        ttl         => 300,
      }

    @example A TXT record at the apex
      noderings_dns_record { 'spf':
        zone        => 'example.com',
        record_name => '@',
        type        => 'TXT',
        values      => ['v=spf1 include:_spf.example.net -all'],
      }
  DESC

  ensurable do
    desc 'Whether the record set should exist.'
    defaultvalues
    defaultto(:present)
  end

  newparam(:name, namevar: true) do
    desc <<~DESC
      A title for the record set. A title of the form `zone/record_name/TYPE`, such as
      `example.com/www/A`, also sets `zone`, `record_name` and `type`; `puppet resource`
      lists record sets that way.
    DESC
  end

  newparam(:zone) do
    desc 'Name or ID of the zone, which must already exist. Required unless the title is zone/record_name/TYPE.'
    munge { |v| v.to_s.strip.downcase.chomp('.') }
    defaultto { (m = PuppetX::Noderings::TypeHelpers::RECORD_TITLE.match(@resource[:name].to_s)) && m[1].downcase.chomp('.') }
  end

  newparam(:record_name) do
    desc 'Name relative to the zone, such as www, or @ for the apex. A full name inside the zone also works. Defaults to the title.'
    defaultto { (m = PuppetX::Noderings::TypeHelpers::RECORD_TITLE.match(@resource[:name].to_s)) ? m[2] : @resource[:name] }
  end

  newparam(:type) do
    desc 'Record type, such as A, AAAA, CNAME, MX or TXT. Required unless the title is zone/record_name/TYPE.'
    defaultto { (m = PuppetX::Noderings::TypeHelpers::RECORD_TITLE.match(@resource[:name].to_s)) && m[3].upcase }
    munge { |v| v.to_s.upcase }
    validate do |v|
      raise ArgumentError, "type must be one of #{PuppetX::Noderings::DNS::RECORD_TYPES.join(', ')}" unless PuppetX::Noderings::DNS::RECORD_TYPES.include?(v.to_s.upcase)
    end
  end

  newproperty(:values, array_matching: :all) do
    desc <<~DESC
      Record values. Write hostnames with a trailing dot. TXT values are plain text:
      the provider quotes them and splits long ones, so do not add quotes.
    DESC
    munge { |v| v.to_s.strip }

    def insync?(is)
      PuppetX::Noderings::DNS.same_values?(resource[:type], is, should)
    end

    def should_to_s(value)
      Array(value).inspect
    end

    def is_to_s(value)
      Array(value).inspect
    end
  end

  newproperty(:ttl) do
    desc 'Time to live in seconds, from 30 to 86400.'
    defaultto(3600)
    munge(&:to_i)
    validate do |v|
      raise ArgumentError, 'ttl must be between 30 and 86400 seconds' unless v.to_s =~ %r{\A\d+\z} && v.to_i.between?(30, 86_400)
    end
  end

  PuppetX::Noderings::TypeHelpers.add_api_params(self)

  autorequire(:noderings_dns_zone) { [self[:zone]] }

  validate do
    raise ArgumentError, 'zone is required' if self[:zone].to_s.empty?
    raise ArgumentError, 'type is required' if self[:type].to_s.empty?

    values = Array(self[:values])
    unless values.empty?
      error = PuppetX::Noderings::DNS.validate_values(self[:type], values)
      raise ArgumentError, "#{self[:record_name]} #{self[:type]}: #{error}" if error
    end
  end
end
