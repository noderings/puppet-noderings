# @summary Stores the NodeRings API credentials for the noderings_* types.
#
# Writes `noderings.yaml` in the Puppet confdir, readable only by its owner. The
# noderings_* types read it when a resource has no `api_token` of its own and the
# `NODERINGS_TOKEN` environment variable is not set. Declare this class on the
# nodes that apply noderings_* resources.
#
# @example Token from Hiera, encrypted with hiera-eyaml
#   class { 'noderings':
#     api_token => Sensitive(lookup('noderings::api_token')),
#   }
#
# @param api_token
#   The NodeRings service account token. Create one in the NodeRings console under
#   Organization, Access Control, Service accounts.
# @param api_url
#   The NodeRings API endpoint.
# @param organization_id
#   The organization to act in, for tokens that can reach more than one.
# @param config_file
#   Where to write the settings. The types read `noderings.yaml` in the Puppet confdir.
# @param owner
#   Owner of the settings file.
# @param group
#   Group of the settings file.
# @param ensure
#   `absent` removes the settings file.
class noderings (
  Optional[Sensitive[String[1]]] $api_token = undef,
  Stdlib::HTTPSUrl $api_url = 'https://api.noderings.com',
  Optional[String[1]] $organization_id = undef,
  Stdlib::Absolutepath $config_file = "${settings::confdir}/noderings.yaml",
  String[1] $owner = 'root',
  String[1] $group = '0',
  Enum['present', 'absent'] $ensure = 'present',
) {
  if $ensure == 'present' and $api_token =~ Undef {
    fail('noderings: api_token is required')
  }

  if $ensure == 'present' {
    $file_ensure = 'file'
    $content = Sensitive(epp('noderings/noderings.yaml.epp', {
      'api_token'       => $api_token,
      'api_url'         => $api_url,
      'organization_id' => $organization_id,
    }))
  } else {
    $file_ensure = 'absent'
    $content = undef
  }

  file { $config_file:
    ensure    => $file_ensure,
    owner     => $owner,
    group     => $group,
    mode      => '0600',
    content   => $content,
    show_diff => false,
  }
}
