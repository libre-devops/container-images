#!/usr/bin/env bash
# Installs pinned tools from versions.lock.json, each checked against its
# SHA-256, for CI runners and local development. Needs only bash, curl,
# python3 and the usual unpacking tools, so it can bootstrap uv itself.
#
# Usage: scripts/ci-tools.sh <tool>...
#
# Installs into $TOOLS_DIR (default: $RUNNER_TEMP/tools in GitHub Actions,
# .tools locally), adds that to the GitHub Actions PATH when run there, and
# prints the bin directory.

set -euo pipefail

cd "$(dirname "$0")/.."
if [ -n "${TOOLS_DIR:-}" ]; then
	dir=$TOOLS_DIR
elif [ -n "${RUNNER_TEMP:-}" ]; then
	dir=$RUNNER_TEMP/tools
else
	dir=$PWD/.tools
fi

for tool in "$@"; do
	spec=$(
		python3 - "$tool" <<'PY'
import json
import sys

tool = sys.argv[1]
versions = json.load(open("versions.lock.json"))["tools"].get(tool)
if not versions:
    sys.exit(f"ci-tools: {tool} is not pinned in versions.lock.json")
if len(versions) != 1:
    sys.exit(f"ci-tools: {tool} has {len(versions)} pinned versions; expected one")
(assets,) = versions.values()
print(" ".join(f"{arch}|{a['url']}|{a['sha256']}" for arch, a in sorted(assets.items())))
PY
	)
	sh images/common/fetch-tool.sh "$dir" "$tool" "$spec" >&2
done

if [ -n "${GITHUB_PATH:-}" ]; then
	echo "$dir/usr/local/bin" >>"$GITHUB_PATH"
fi
echo "$dir/usr/local/bin"
