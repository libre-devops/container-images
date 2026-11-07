#!/usr/bin/env bash
# Runs the smoke tests for one image: the shared checks, each of the image's
# suites (the toolbox runs every included image's), and a write check as an
# arbitrary uid in group 0. Each test script is piped to bash inside the
# container, so nothing is mounted and the tests behave the same under
# Docker, rootless Podman and SELinux.
#
# Usage: tests/run.sh <image> <reference> [version]
#   version  Defaults to the image's latest version in versions.yml; it sets
#            the versions the tests expect.

set -euo pipefail

image=${1:?usage: tests/run.sh <image> <reference> [version]}
ref=${2:?usage: tests/run.sh <image> <reference> [version]}
version=${3:-}
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
engine=$("$root/scripts/engine.sh")
images=(uv run --quiet "$root/scripts/images.py")

env_args=()
while IFS= read -r kv; do
	env_args+=(-e "$kv")
done < <("${images[@]}" test-env "$image" "$version")
mapfile -t suites < <("${images[@]}" test-suites "$image")

run() {
	"$engine" run --rm -i "${env_args[@]}" "$@"
}

echo "== $ref: shared checks"
run "$ref" bash -s <"$here/common.sh"
for suite in "${suites[@]}"; do
	echo "== $ref: $suite checks"
	run "$ref" bash -s <"$here/$suite.sh"
done
echo "== $ref: arbitrary uid in group 0"
run --user 4242:0 "$ref" bash -s <"$here/arbitrary-uid.sh"
echo "== $ref: all smoke tests passed"
