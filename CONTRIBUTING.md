# Contributing

Thanks for helping improve the noderings module.

1. Open an issue describing the bug or change before large pull requests.
2. Fork the repository and create a topic branch.
3. Run `bundle exec rake test`. Lint, syntax, RuboCop, metadata and unit tests
   must pass.
4. Add tests for new behaviour: type specs in `spec/unit/puppet/type`, provider
   specs in `spec/unit/puppet/provider` (they apply catalogs against the
   in-memory API in `spec/support/fake_noderings.rb`), and acceptance tests in
   `spec/acceptance` for anything that changes what reaches the API.
5. Regenerate the reference with `bundle exec rake strings:generate:reference`
   when you change documentation in types or classes.
6. Use [Conventional Commits](https://www.conventionalcommits.org/) and sign off
   each commit (`git commit -s`) to certify the
   [Developer Certificate of Origin](https://developercertificate.org/).

The files marked "Managed by modulesync" follow the
[Vox Pupuli modulesync defaults](https://github.com/voxpupuli/modulesync_config);
module-specific settings for them live in `.sync.yml`.

Please report security problems privately as described in [SECURITY.md](SECURITY.md).
