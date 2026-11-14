#!/usr/bin/env bash
# Logs in to a container registry, retrying with backoff: dhi.io and Docker Hub
# now and then refuse a valid login (401) when many jobs log in at once, and a
# refused login would otherwise fail the job.
#
# Usage: REGISTRY_USERNAME=... REGISTRY_PASSWORD=... scripts/registry-login.sh <registry>

set -euo pipefail

registry=${1:?usage: scripts/registry-login.sh <registry>}
: "${REGISTRY_USERNAME:?set REGISTRY_USERNAME}" "${REGISTRY_PASSWORD:?set REGISTRY_PASSWORD}"
engine=$(dirname "$0")/engine.sh
engine=$("$engine")

for attempt in 1 2 3 4 5; do
	if printf '%s' "$REGISTRY_PASSWORD" |
		"$engine" login "$registry" --username "$REGISTRY_USERNAME" --password-stdin >/dev/null; then
		echo "registry-login: logged in to $registry"
		exit 0
	fi
	[ "$attempt" -lt 5 ] || break
	echo "registry-login: $registry refused the login (attempt $attempt), retrying in $((attempt * 15))s" >&2
	sleep $((attempt * 15))
done
echo "registry-login: could not log in to $registry" >&2
exit 1
