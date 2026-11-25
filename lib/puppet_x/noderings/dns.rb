# frozen_string_literal: true

#
# Copyright:: NodeRings
# License:: Apache-2.0
#
# DNS name and record-value helpers.

require 'ipaddr'

require_relative 'client'

module PuppetX
  module Noderings
    module DNS
      RECORD_TYPES = %w[
        A AAAA ALIAS CAA CERT CNAME DNAME DS HINFO HTTPS LOC MX NAPTR NS OPENPGPKEY
        PTR RP SMIMEA SRV SSHFP SVCB TLSA TXT
      ].freeze
      SINGLE_VALUE_TYPES = %w[CNAME DNAME ALIAS].freeze
      NAME_TYPES = %w[CNAME DNAME ALIAS NS PTR].freeze

      module_function

      def normalize_zone_name(name)
        name.to_s.strip.downcase.chomp('.')
      end

      # www.example.com. in example.com -> www; the apex -> @
      def relative_name(name, zone)
        n = name.to_s.strip.downcase
        z = normalize_zone_name(zone)
        return '@' if ['', '@'].include?(n)

        n = n.chomp('.')
        unless z.empty?
          return '@' if n == z

          n = n.delete_suffix(".#{z}") if n.end_with?(".#{z}")
        end
        n
      end

      def ip(value)
        IPAddr.new(value.to_s.strip)
      rescue ArgumentError
        nil
      end

      # An error message, or nil when the values are acceptable.
      def validate_values(type, values)
        return 'at least one record value is required' if values.empty?
        return "#{type} records take exactly one value" if SINGLE_VALUE_TYPES.include?(type) && values.length > 1

        values.each do |v|
          v = v.to_s
          return 'record values must not be empty' if v.strip.empty?

          addr = %w[A AAAA ALIAS].include?(type) ? ip(v) : nil
          return "#{v.inspect} is not an IPv4 address" if type == 'A' && !addr&.ipv4?
          return "#{v.inspect} is not an IPv6 address" if type == 'AAAA' && (!addr&.ipv6? || addr.ipv4_mapped?)
          return 'ALIAS must point to a hostname, not an address' if type == 'ALIAS' && addr
          return 'TXT values are limited to 4096 characters' if type == 'TXT' && v.length > 4096
        end
        nil
      end

      def fqdn(host)
        h = host.to_s.strip.downcase
        return h if ['', '.'].include?(h)

        "#{h.chomp('.')}."
      end

      # A comparable form of one value: the API may lowercase names or add trailing dots.
      def canonical(type, value)
        v = value.to_s.strip
        return v if type == 'TXT'

        if %w[A AAAA].include?(type)
          addr = ip(v)
          return addr ? addr.to_s : v.downcase
        end
        return fqdn(v) if NAME_TYPES.include?(type)

        f = v.split
        return "#{f.first} #{fqdn(f[1])}" if type == 'MX' && f.length == 2
        return "#{f[0, 3].join(' ')} #{fqdn(f[3])}" if type == 'SRV' && f.length == 4

        v.downcase.split.join(' ')
      end

      def same_values?(type, left, right)
        Array(left).map { |x| canonical(type, x) }.sort == Array(right).map { |x| canonical(type, x) }.sort
      end

      # Splits a TXT value into 255-byte quoted strings, as the API expects.
      def quote_txt(value)
        raw = value.to_s.b
        parts = []
        while raw.bytesize > 255
          cut = 255
          cut -= 1 while cut.positive? && (raw.getbyte(cut) & 0xC0) == 0x80
          parts << raw.byteslice(0, cut)
          raw = raw.byteslice(cut, raw.bytesize - cut)
        end
        parts << raw
        parts.map do |p|
          s = p.force_encoding('UTF-8').gsub('\\') { '\\\\' }.gsub('"') { '\\"' }
          "\"#{s}\""
        end.join(' ')
      end

      # Joins the API's quoted TXT strings back into one value.
      def unquote_txt(value)
        v = value.to_s.strip
        return v unless v.start_with?('"')

        out = +''
        inside = false
        i = 0
        while i < v.length
          c = v[i]
          if c == '"'
            inside = !inside
          elsif c == '\\' && inside && i + 1 < v.length
            i += 1
            out << v[i]
          elsif inside
            out << c
          end
          i += 1
        end
        out
      end

      def to_api(type, value)
        (type == 'TXT') ? quote_txt(value) : value.to_s.strip
      end

      def from_api(type, value)
        (type == 'TXT') ? unquote_txt(value) : value.to_s.strip
      end

      # The zone with this name or ID, or nil.
      def find_zone(client, zone)
        z = normalize_zone_name(zone)
        client.list_dns_zones.find { |x| x['id'] == zone || normalize_zone_name(x['name']) == z }
      end

      # The record set with exactly this relative name and type, or nil. The
      # API's name filter matches substrings, and the apex is listed unfiltered.
      def find_record(client, zone_id, name, type)
        client.list_dns_records(zone_id, name: (name == '@') ? nil : name, type: type).find do |r|
          relative_name(r['name'], '') == name && r['type'].to_s.upcase == type && !r['system']
        end
      end
    end
  end
end
