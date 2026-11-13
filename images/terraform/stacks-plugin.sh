#!/bin/sh
# Puts the pinned Terraform Stacks plugin (tfstacks) where `terraform stacks`
# looks for it, in the app user's plugin cache. Terraform then fetches only the
# small manifest from HCP Terraform (or TF_STACKS_HOSTNAME) and uses this
# binary while that manifest names the same version, rather than downloading
# it. It is a plugin, not a command: Terraform runs it.
#
# Usage: stacks-plugin.sh <tfstacks binary> <version> <home>

set -eu

[ "$#" -eq 3 ] || {
	echo "usage: stacks-plugin.sh <tfstacks binary> <version> <home>" >&2
	exit 1
}
case $(uname -m) in
x86_64 | amd64) arch=amd64 ;;
aarch64 | arm64) arch=arm64 ;;
*)
	echo "stacks-plugin: unsupported architecture: $(uname -m)" >&2
	exit 1
	;;
esac
dir=$3/.terraform.d/stacksplugin/bin/linux_$arch
mkdir -p "$dir"
install -m 0755 "$1" "$dir/tfstacks"
printf '%s' "$2" >"$dir/.version"
echo "stacks-plugin: tfstacks $2 cached in $dir"
