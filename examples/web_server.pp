# A web server on NodeRings: an SSH key, a firewall that allows SSH from an
# office and HTTPS from anywhere, the VM, and a signed DNS zone.
#
#   NODERINGS_TOKEN=... puppet apply examples/web_server.pp
#
# The VM is billed by the hour until it is removed with ensure => absent.
noderings_ssh_key { 'deploy':
  public_key => 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyReplaceWithYourOwn deploy@example',
}

noderings_firewall_ruleset { 'web':
  rules => [
    {
      'direction'         => 'ingress',
      'action'            => 'accept',
      'protocol'          => 'tcp',
      'destination_ports' => '22',
      'source'            => { 'cidrs' => ['198.51.100.0/24'] },
    },
    {
      'direction'         => 'ingress',
      'action'            => 'accept',
      'protocol'          => 'tcp',
      'destination_ports' => '443',
      'source'            => { 'cidrs' => ['0.0.0.0/0'] },
    },
  ],
}

noderings_vm { 'web-1':
  plan             => 'SC-GC-1C-1G-20',
  country          => 'United States',
  city             => 'Ashburn',
  distro           => 'ubuntu_24_04',
  ssh_keys         => ['deploy'],
  tags             => ['web'],
  firewall_ruleset => 'web',
}

noderings_dns_zone { 'example.com':
  dnssec => true,
}

noderings_dns_record { 'www':
  zone   => 'example.com',
  type   => 'CNAME',
  values => ['web-1.example.net.'],
}
