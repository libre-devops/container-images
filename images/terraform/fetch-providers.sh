#!/bin/sh
# Lays out a Terraform filesystem mirror (the "packed" layout: the release
# zips themselves, so lock files' zh: hashes still match) of every provider
# release in TERRAFORM_PROVIDERS for this machine's architecture, each checked
# against its pinned SHA-256.
#
# TERRAFORM_PROVIDERS comes from versions.lock.json, through
# scripts/images.py: space-separated "<arch>|<source>|<version>|<url>|<sha256>"
# items, where <source> is <namespace>/<type> on registry.terraform.io.
#
# Usage: fetch-providers.sh <mirror directory>

set -eu

die() {
	printf 'fetch-providers: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 1 ] || die "usage: fetch-providers.sh <mirror directory>"
mirror=$1
: "${TERRAFORM_PROVIDERS:?}"

case $(uname -m) in
x86_64 | amd64) arch=amd64 ;;
aarch64 | arm64) arch=arm64 ;;
*) die "unsupported architecture: $(uname -m)" ;;
esac

count=0
for item in $TERRAFORM_PROVIDERS; do
	case $item in
	"$arch|"*) ;;
	*) continue ;;
	esac
	rest=${item#*|}
	source=${rest%%|*}
	rest=${rest#*|}
	version=${rest%%|*}
	rest=${rest#*|}
	url=${rest%|*}
	sha=${rest##*|}
	type=${source#*/}
	dest=$mirror/registry.terraform.io/$source
	file=$dest/terraform-provider-${type}_${version}_linux_${arch}.zip
	mkdir -p "$dest"
	curl -fsSL --retry 5 --retry-connrefused -o "$file" "$url"
	actual=$(sha256sum "$file" | cut -d ' ' -f 1)
	[ "$actual" = "$sha" ] || die "SHA-256 mismatch for $source $version: pinned $sha, downloaded $actual"
	echo "fetch-providers: $source $version matches its pinned SHA-256"
	count=$((count + 1))
done
[ "$count" -gt 0 ] || die "no providers for $arch in TERRAFORM_PROVIDERS"
