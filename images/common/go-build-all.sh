#!/bin/sh
# Builds every Go tool a build asked for, each into its own root under <dir>
# (<dir>/shfmt, <dir>/tenv and so on). A tool is asked for by setting its
# <TOOL>_GO build argument; the others are skipped.
#
# Usage: go-build-all.sh <dir>

set -eu

dir=${1:?usage: go-build-all.sh <dir>}
lib=$(dirname "$0")

for tool in shfmt tenv tflint terraform-docs conftest; do
	var=$(echo "$tool" | tr 'a-z-' 'A-Z_')_GO
	eval "spec=\${$var:-}"
	if [ -n "$spec" ]; then
		sh "$lib/go-build.sh" "$dir/$tool" "$spec"
	fi
done
