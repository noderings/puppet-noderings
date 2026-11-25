# frozen_string_literal: true

require_relative '../../puppet_x/noderings/type_helpers'

Puppet::Type.newtype(:noderings_ssh_key) do
  desc <<~DESC
    Manages an SSH public key stored in a NodeRings organization. `noderings_vm`
    installs stored keys on new virtual machines.

    @example Store a key
      noderings_ssh_key { 'deploy':
        ensure     => present,
        public_key => 'ssh-ed25519 AAAAC3Nza... deploy@example',
      }

    @example List the stored keys
      $ puppet resource noderings_ssh_key
  DESC

  ensurable do
    desc 'Whether the key should be stored.'
    defaultvalues
    defaultto(:present)
  end

  newparam(:name, namevar: true) do
    desc 'Name of the key in NodeRings.'
    validate { |v| raise ArgumentError, 'name must not be empty' if v.to_s.strip.empty? }
  end

  newproperty(:public_key) do
    desc <<~DESC
      The OpenSSH public key, such as the contents of `id_ed25519.pub`. Only the key
      type and body are compared; the comment is ignored. A changed key is replaced.
    DESC
    munge(&:strip)
    validate do |v|
      raise ArgumentError, 'public_key must look like "ssh-ed25519 AAAA..."' unless v.to_s.strip =~ %r{\A\S+ \S+}
    end

    def insync?(is)
      is.to_s.split[0, 2] == should.to_s.split[0, 2]
    end
  end

  PuppetX::Noderings::TypeHelpers.add_api_params(self)
end
