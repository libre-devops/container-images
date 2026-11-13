#!/bin/sh
# Writes azure-terraform's two Terraform CLI configurations, for the providers
# in the mirror at <dir>/providers:
#
#   airgapped.tfrc  The mirrored providers install only from the mirror, so
#                   terraform init needs no registry for them; anything else
#                   still comes from the registry. The default
#                   (TF_CLI_CONFIG_FILE).
#   registry.tfrc   Everything from the registry, as plain Terraform does: for
#                   a version the mirror does not have, when the registry is
#                   reachable.
#
# Terraform cannot fall back from one to the other: a provider that may come
# from the registry makes terraform init query it, which fails offline.
#
# Usage: cli-configs.sh <dir>

set -eu

dir=${1:?usage: cli-configs.sh <dir>}
mirror=$dir/providers
[ -d "$mirror/registry.terraform.io" ] || {
	echo "cli-configs: no provider mirror at $mirror" >&2
	exit 1
}

sources=$(cd "$mirror" && find registry.terraform.io -mindepth 2 -maxdepth 2 -type d | sort)
list=$(printf '%s\n' "$sources" | sed 's/.*/    "&",/')

cat >"$dir/airgapped.tfrc" <<TFRC
# azure-terraform: the mirrored providers come only from the local mirror, so
# terraform init needs no registry for them. Set
# TF_CLI_CONFIG_FILE=$dir/registry.tfrc to use the registry instead.
provider_installation {
  filesystem_mirror {
    path    = "$mirror"
    include = [
$list
    ]
  }
  direct {
    exclude = [
$list
    ]
  }
}
TFRC

cat >"$dir/registry.tfrc" <<'TFRC'
# azure-terraform: every provider from the registry, as plain Terraform does.
provider_installation {
  direct {}
}
TFRC

chmod 0644 "$dir/airgapped.tfrc" "$dir/registry.tfrc"
echo "cli-configs: $(printf '%s\n' "$sources" | wc -l) mirrored providers"
