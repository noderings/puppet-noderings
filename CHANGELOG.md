# Changelog

All notable changes to this project will be documented in this file.
Each new release typically also includes the latest modulesync defaults.
These should not affect the functionality of the module.

## [v0.1.0](https://github.com/noderings/puppet-noderings/tree/v0.1.0) (2026-11-25)

**Implemented enhancements:**

- `noderings_vm`: order virtual machines from the NodeRings marketplace and keep their distro (with `allow_reinstall`), tags, firewall ruleset and power state; delete them
- `noderings_dns_zone` with optional DNSSEC signing; `puppet resource` shows its nameservers and DS record
- `noderings_dns_record`: record sets of every supported type, with TXT quoting and value validation
- `noderings_firewall_ruleset`: ordered firewall rules, reconciled in place
- `noderings_ssh_key`: SSH public keys for new virtual machines
- `noderings` class: stores the API credentials in `noderings.yaml`
- Every type supports `puppet resource` listing
