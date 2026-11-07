#!/usr/bin/env bash
# Builds one image locally with Docker or Podman, for the machine's own
# platform, using the same build arguments CI uses. Build output goes to
# stderr; the image reference is printed on stdout.
#
# Usage: scripts/build.sh <image> [version] [base]
#   version  Defaults to the image's latest version in versions.yml.
#   base     A key under bases or portability in versions.yml, or a full image
#            reference, to build on another base.

set -euo pipefail

cd "$(dirname "$0")/.."
image=${1:?usage: scripts/build.sh <image> [version] [base]}
version=${2:-}
base=${3:-}
engine=$(scripts/engine.sh)
images=(uv run --quiet scripts/images.py)

ref=$("${images[@]}" local-ref "$image" "$version" --base "$base")
args=()
while IFS= read -r kv; do
	args+=(--build-arg "$kv")
done < <("${images[@]}" build-args "$image" "$version" --base "$base")
while IFS= read -r kv; do
	args+=(--label "$kv")
done < <("${images[@]}" labels "$image" "$version")

"$engine" build "${args[@]}" -f images/Containerfile --target "$image" -t "$ref" . >&2
echo "$ref"
