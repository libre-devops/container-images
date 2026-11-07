#!/bin/sh
# Fetches every pinned download a build asked for, each into its own root
# under <dir> so that later stages copy exactly the ones they need:
# <dir>/common (ShellCheck and jq, in every image), <dir>/uv, <dir>/ldo-cli
# and <dir>/powershell. A download is asked for by setting its <TOOL>_ASSET
# build argument; the others are skipped.
#
# Usage: fetch-all.sh <dir>

set -eu

dir=${1:?usage: fetch-all.sh <dir>}
lib=$(dirname "$0")

sh "$lib/fetch-tool.sh" "$dir/common" shellcheck "${SHELLCHECK_ASSET:?}"
sh "$lib/fetch-tool.sh" "$dir/common" jq "${JQ_ASSET:?}"
for tool in uv ldo-cli powershell; do
	var=$(echo "$tool" | tr 'a-z-' 'A-Z_')_ASSET
	eval "spec=\${$var:-}"
	if [ -n "$spec" ]; then
		sh "$lib/fetch-tool.sh" "$dir/$tool" "$tool" "$spec"
	fi
done
