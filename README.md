# noderings

[![License](https://img.shields.io/github/license/noderings/puppet-noderings.svg)](https://github.com/noderings/puppet-noderings/blob/main/LICENSE)
[![CI](https://github.com/noderings/puppet-noderings/actions/workflows/ci.yml/badge.svg)](https://github.com/noderings/puppet-noderings/actions/workflows/ci.yml)
[![Puppet Forge](https://img.shields.io/puppetforge/v/noderings/noderings.svg)](https://forge.puppet.com/modules/noderings/noderings)

#### Table of Contents

1. [Overview](#overview)
1. [Setup](#setup)
1. [Usage](#usage)
1. [Reference](#reference)
1. [Limitations](#limitations)
1. [Development](#development)

## Overview

Manage [NodeRings](https://noderings.com) from OpenVox or Puppet: virtual
machines ordered from the NodeRings marketplace, DNS zones and records (with
DNSSEC), firewall rulesets and SSH keys. The module is also a
[Bolt inventory plugin](#bolt-inventory-plugin) that turns your NodeRings VMs into
Bolt targets.

New to it? The step-by-step guide [How to use Puppet and OpenVox on NodeRings to order a VPS](https://noderings.com/blog/puppet-vps) walks through a first run.

```puppet
noderings_ssh_key { 'deploy':
  public_key => 'ssh-ed25519 AAAAC3Nza... deploy@example',
}

noderings_firewall_ruleset { 'web':
  rules => [
    { 'direction' => 'ingress', 'action' => 'accept', 'protocol' => 'tcp', 'destination_ports' => '22', 'source' => { 'cidrs' => ['198.51.100.0/24'] } },
    { 'direction' => 'ingress', 'action' => 'accept', 'protocol' => 'tcp', 'destination_ports' => '443', 'source' => { 'cidrs' => ['0.0.0.0/0'] } },
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
```

The types call the NodeRings API, so they can run on any node: a management node,
a node that runs `puppet apply`, or the primary server's own agent. They need no
packages; the providers use the Ruby that ships with the agent.

## Setup

### Requirements

* OpenVox 8 or 9, or Puppet 8
* [puppetlabs/stdlib](https://forge.puppet.com/modules/puppetlabs/stdlib) 9 or later
* A NodeRings service account token. Create one in the NodeRings console under
  **Organization → Access Control → Service accounts**, with the permissions for
  the resources you manage.
* For `noderings_vm`: a payment method or credit on the organization. Ordering a
  virtual machine is billed.

### Installation

```shell
puppet module install noderings-noderings
```

or in a `Puppetfile`:

```ruby
mod 'noderings/noderings'
```

### Credentials

Declare the `noderings` class on the nodes that apply noderings_* resources. It
writes `noderings.yaml` in the Puppet confdir, readable only by root:

```puppet
class { 'noderings':
  api_token => Sensitive(lookup('noderings::api_token')),
}
```

Keep the token encrypted in Hiera, for example with
[hiera-eyaml](https://github.com/voxpupuli/hiera-eyaml). Each type finds the
token in this order:

1. its own `api_token` parameter (pass it as `Sensitive`),
2. the `NODERINGS_TOKEN` environment variable of the agent,
3. `noderings.yaml` written by the `noderings` class.

`api_url` and `organization_id` work the same way, with the `NODERINGS_API_URL`
and `NODERINGS_ORGANIZATION_ID` environment variables.

## Usage

### Virtual machines

`noderings_vm` orders the cheapest marketplace offer for the plan in the city
when no VM has the hostname, or the best rated one with `sort => rating`:

```puppet
noderings_vm { 'web-1':
  ensure           => present,
  plan             => 'SC-GC-1C-1G-20',
  country          => 'United States',
  city             => 'Ashburn',
  billing_type     => 'usage',
  distro           => 'debian_13',
  ssh_keys         => ['deploy'],
  tags             => ['web', 'production'],
  firewall_ruleset => 'web',
  power_state      => 'running',
}
```

Without `hosting_provider` the provider can change between orders. Set it to
keep one provider: it takes the provider's ID, its storefront slug (such as
`acme-hosting`) or its name (`Acme Hosting`, any case). A name that more than
one provider uses fails; give the ID or slug then. The parameter is not called
`provider` because Puppet reserves that name. `provider_id` still works and
takes precedence.

On an existing VM, Puppet keeps `tags`, `firewall_ruleset` (an empty string
detaches it) and `power_state` as declared. The plan is never changed. A
different `distro` fails the run unless `allow_reinstall => true`, because
reinstalling erases the disk. `ensure => absent` deletes the VM: an hourly VM
stops billing, and a monthly subscription is cancelled without a refund.

Orders carry an idempotency key, so a lost response is retried without ordering
a second VM. To see what is on offer, use the NodeRings console marketplace, or
`knife noderings plan list` from
[knife-noderings](https://github.com/noderings/knife-noderings).

List the organization's VMs with their addresses:

```shell
puppet resource noderings_vm
```

### DNS

```puppet
noderings_dns_zone { 'example.com':
  dnssec => true,
}

noderings_dns_record { 'www':
  zone   => 'example.com',
  type   => 'A',
  values => ['192.0.2.10', '192.0.2.11'],
  ttl    => 300,
}

noderings_dns_record { 'mail':
  zone        => 'example.com',
  record_name => '@',
  type        => 'MX',
  values      => ['10 mx1.example.net.', '20 mx2.example.net.'],
}

noderings_dns_record { 'spf':
  zone        => 'example.com',
  record_name => '@',
  type        => 'TXT',
  values      => ['v=spf1 include:_spf.example.net -all'],
}
```

A record resource manages one name and type as a set: the values replace whatever
the set held. Write hostnames with a trailing dot. TXT values are plain text; the
provider quotes them and splits long ones. `puppet resource noderings_dns_zone`
shows the nameservers to set at your registrar and the DS record of a signed zone.

### Firewall rulesets

A ruleset holds exactly the rules listed, in order:

```puppet
noderings_firewall_ruleset { 'web':
  rules => [
    { 'direction' => 'ingress', 'action' => 'accept', 'protocol' => 'tcp', 'destination_ports' => '22', 'source' => { 'address_groups' => ['office'] } },
    { 'direction' => 'ingress', 'action' => 'accept', 'protocol' => 'tcp', 'destination_ports' => '443', 'source' => { 'cidrs' => ['0.0.0.0/0'] } },
    { 'direction' => 'ingress', 'action' => 'accept', 'protocol' => 'tcp', 'destination_ports' => '443', 'source' => { 'cidrs' => ['::/0'] } },
    { 'direction' => 'ingress', 'action' => 'drop', 'protocol' => 'any', 'source' => { 'cidrs' => ['0.0.0.0/0'] } },
  ],
}
```

Each rule takes `direction` (`ingress` or `egress`), `action` (`accept` or
`drop`), `protocol` (`tcp` by default), `source` and `destination` (each with
`cidrs`, `address_groups`, `address_group_ids` or `vm_tags`), and optional
`source_ports` and `destination_ports` (one port or one range). Rules are checked
before any API call. Changes keep matching rules and their IDs, update changed
ones in place and move them into order.

### Relationships

`noderings_vm` automatically requires the `noderings_ssh_key` and
`noderings_firewall_ruleset` resources it names, and `noderings_dns_record`
requires its `noderings_dns_zone`. Every type requires the `noderings.yaml` file.

## Bolt inventory plugin

The module is also a [Bolt](https://www.puppet.com/docs/bolt) inventory plugin.
It lists your NodeRings VMs as Bolt targets, so `bolt command run`, tasks and
plans reach every VM without a hand-written target list. New VMs show up the next
time Bolt reads the inventory.

Add the module to your Bolt project:

```shell
bolt module add noderings-noderings
```

Then reference the plugin in `inventory.yaml`:

```yaml
groups:
  - name: noderings
    targets:
      - _plugin: noderings
        token:
          _plugin: env_var
          var: NODERINGS_TOKEN
    config:
      transport: ssh
      ssh:
        user: root

  # Only running VMs tagged web, with extra data as target vars.
  - name: web
    targets:
      - _plugin: noderings
        tags: [web]
        target_mapping:
          vars:
            plan: plan_code
            city: region_city
```

```shell
export NODERINGS_TOKEN=nr_...
bolt inventory show --targets noderings --detail
bolt command run 'uptime' --targets web
```

| Option | Default | Description |
|---|---|---|
| `token` | `NODERINGS_TOKEN` on the Bolt controller | API token. Read it with the `env_var` or a secret plugin rather than writing it into the inventory. |
| `api_url` | `https://api.noderings.com` | API URL |
| `organization_id` | the token's organization | Organization to list VMs from |
| `tags` | | Only VMs that have every one of these tags |
| `power_states` | `[running]` | Only VMs in these states, such as `running` or `stopped`; `[all]` for every VM |
| `name_pattern` | | Only VMs whose hostname matches this regular expression |
| `target_mapping` | `name: hostname`, `uri: ipv4` | Where each target field comes from (see below) |

`target_mapping` takes the target fields `name`, `uri`, `alias` and `features` as
a VM field name, and `config`, `facts` and `vars` as a hash of VM field names, for
example `config: { ssh: { host: ipv6 } }`. A field can index into a list, such as
`tags.0`. The VM fields are `id`, `hostname`, `ipv4`, `ipv6`, `power_state`,
`distro`, `plan_code`, `plan_id`, `region_id`, `region_city`, `region_country`,
`provider_name`, `billing_type`, `firewall_ruleset_id`, `tags`, `cpus`,
`memory_mb`, `disk_mb` and `instant_app`. Every target also gets all of them
as the fact `noderings`, so plans can read `$target.facts['noderings']['region_city']`.
VMs that do not have an address yet are left out.

The plugin runs on the Bolt controller and only reads the VM list. It never
changes anything in NodeRings.

## Reference

See [REFERENCE.md](REFERENCE.md) for every type, parameter and property, and the
plugin's `resolve_reference` task.

## Limitations

* The types manage NodeRings objects through its API and do not configure the
  operating system inside a VM. Bootstrap new VMs with your usual tooling, for
  example by adding them to your Puppet infrastructure after they boot.
* A VM's plan, region and provider cannot be changed after it is ordered.
* Rule changes and VM operations wait for the platform to apply them; tune
  `wait_timeout` for slow providers.

## Development

```shell
bundle install
bundle exec rake test          # lint, syntax, RuboCop, metadata and unit tests
```

The unit tests apply real catalogs against an in-memory NodeRings API, so they
need no token. The acceptance tests start an OpenVox agent in a container with
Beaker and call the real API:

```shell
export NODERINGS_TOKEN=...          # a service account token
export NODERINGS_TEST_BILLED=1      # optional: also order, change and delete a billed VM
BEAKER_SETFILE=ubuntu2404-64 BEAKER_PUPPET_COLLECTION=openvox8 bundle exec rake beaker
```

They name every object after `NODERINGS_TEST_ID` and remove what they create.
See [CONTRIBUTING.md](CONTRIBUTING.md).

## Related

The [Go SDK](https://github.com/noderings/noderings-go) is the official Go client for the NodeRings API.

## License

Copyright NodeRings. Licensed under the [Apache License, Version 2.0](LICENSE).
