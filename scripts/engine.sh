#!/usr/bin/env bash
# Prints the container engine to use: $ENGINE if set, else docker if it
# answers (WSL can have a docker command that is only a placeholder), else
# podman.

set -euo pipefail

if [ -n "${ENGINE:-}" ]; then
	echo "$ENGINE"
elif command -v docker >/dev/null 2>&1 && docker version >/dev/null 2>&1; then
	echo docker
elif command -v podman >/dev/null 2>&1; then
	echo podman
else
	echo "engine.sh: neither docker nor podman is installed" >&2
	exit 1
fi
