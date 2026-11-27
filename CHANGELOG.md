# Changelog

All notable changes to this project will be documented in this file.
Each new release typically also includes the latest modulesync defaults.
These should not affect the functionality of the module.

## [0.3.1](https://github.com/noderings/puppet-noderings/compare/v0.3.0...v0.3.1) (2026-11-27)


### Documentation

* link the official Go SDK in the README ([#9](https://github.com/noderings/puppet-noderings/issues/9)) ([39feb25](https://github.com/noderings/puppet-noderings/commit/39feb2557b3fa440a8926d31ed7054d2820d3273))

## [0.3.0](https://github.com/noderings/puppet-noderings/compare/v0.2.0...v0.3.0) (2026-11-27)


### Features

* Bolt inventory plugin ([#7](https://github.com/noderings/puppet-noderings/issues/7)) ([9b285c1](https://github.com/noderings/puppet-noderings/commit/9b285c1125d2f26e7bca00718f369b0b0399e7f4))

## [0.2.0](https://github.com/noderings/puppet-noderings/compare/v0.1.0...v0.2.0) (2026-11-26)


### Features

* choose the provider when ordering a VM ([#4](https://github.com/noderings/puppet-noderings/issues/4)) ([8ea58a9](https://github.com/noderings/puppet-noderings/commit/8ea58a94d5c5b8f011c8d05ac7862c5b247b43a1))

## [v0.1.0](https://github.com/noderings/puppet-noderings/tree/v0.1.0) (2026-11-25)

**Implemented enhancements:**

- `noderings_vm`: order virtual machines from the NodeRings marketplace and keep their distro (with `allow_reinstall`), tags, firewall ruleset and power state; delete them
- `noderings_dns_zone` with optional DNSSEC signing; `puppet resource` shows its nameservers and DS record
- `noderings_dns_record`: record sets of every supported type, with TXT quoting and value validation
- `noderings_firewall_ruleset`: ordered firewall rules, reconciled in place
- `noderings_ssh_key`: SSH public keys for new virtual machines
- `noderings` class: stores the API credentials in `noderings.yaml`
- Every type supports `puppet resource` listing
