#!/bin/sh
# Downloads every Galaxy role in ANSIBLE_ROLES into <dir>, checks each against
# its pinned SHA-256, and writes <dir>/requirements.yml, from which
# `ansible-galaxy role install -r` installs them without the network.
#
# ANSIBLE_ROLES comes from versions.lock.json, through scripts/images.py:
# space-separated "<namespace.name>|<version>|<url>|<sha256>" items.
#
# Usage: fetch-roles.sh <dir>

set -eu

die() {
	printf 'fetch-roles: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 1 ] || die "usage: fetch-roles.sh <dir>"
dir=$1
: "${ANSIBLE_ROLES:?}"

mkdir -p "$dir"
requirements=$dir/requirements.yml
echo "---" >"$requirements"
for item in $ANSIBLE_ROLES; do
	name=${item%%|*}
	rest=${item#*|}
	version=${rest%%|*}
	rest=${rest#*|}
	url=${rest%|*}
	sha=${rest##*|}
	file=$dir/$name.tar.gz
	# --retry-all-errors: a reset connection is not one of the errors --retry
	# covers on its own. The SHA-256 check below catches a bad file.
	curl -fsSL --retry 5 --retry-all-errors -o "$file" "$url"
	actual=$(sha256sum "$file" | cut -d ' ' -f 1)
	[ "$actual" = "$sha" ] || die "SHA-256 mismatch for $name $version: pinned $sha, downloaded $actual"
	echo "fetch-roles: $name $version matches its pinned SHA-256"
	printf -- '- name: %s\n  src: %s\n  version: "%s"\n' "$name" "$file" "$version" >>"$requirements"
done
