#!/bin/sh
# Unpacks a CI agent from its pinned tarball (already checked against its
# SHA-256 by fetch-tool.sh) into the directory it runs from, and installs the
# script that registers and starts it. The agent writes its registration and
# its jobs' work into that directory, so it belongs to the app user and is
# group-writable for gid 0, for an arbitrary uid in group 0 (OpenShift).
#
# Usage: install.sh <tarball directory> <agent directory> <start script> <command name>

set -eu

die() {
	printf 'agent install: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 4 ] || die "usage: install.sh <tarball directory> <agent directory> <start script> <command name>"
archives=$1
dest=$2
start=$3
name=$4

set -- "$archives"/*.tar.gz
[ "$#" -eq 1 ] && [ -f "$1" ] || die "expected exactly one tarball in $archives"
mkdir -p "$dest"
tar -xzf "$1" -C "$dest"
# The agents run tasks with the Node runtimes they bundle, but never npm, npx
# or corepack, whose own bundled dependencies carry known vulnerabilities.
# Remove them: a job that needs npm installs Node itself (actions/setup-node,
# the NodeTool task).
for node in "$dest"/externals/node*; do
	[ -d "$node" ] || continue
	rm -rf "$node/lib/node_modules/npm" "$node/lib/node_modules/corepack" \
		"$node/bin/npm" "$node/bin/npx" "$node/bin/corepack"
done
chown -R 10001:0 "$dest"
chmod -R g=u "$dest"
install -m 0755 "$start" "/usr/local/bin/$name"
echo "agent install: $(basename "$1") in $dest, started by $name"
