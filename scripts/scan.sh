#!/usr/bin/env bash
# Scans an image with Trivy and applies the gate used on pull requests,
# releases and the daily scan: fail on any critical vulnerability, or on any
# high one with a fix available.
#
# Usage: scripts/scan.sh <image reference> [image] [version] [base]
#
# Two sets of VEX statements are applied, and nothing else is excused:
#   - vex/libre-devops.openvex.json: findings this repository has examined and
#     shown not to apply, each with its reason.
#   - With [image] (and [version], [base] as for `just build`): the statements
#     the base image's publisher attached to its pinned digest, such as Docker
#     Hardened Images' records of packages they have patched in place.
# .trivyignore.yaml holds any time-boxed exceptions, each with an expiry.
#
# A reference in the local Docker or Podman store is scanned from there;
# anything else is pulled from its registry. Set SCAN_REPORT to keep the JSON
# report.

set -euo pipefail

cd "$(dirname "$0")/.."
ref=${1:?usage: scripts/scan.sh <image reference> [image] [version] [base]}
image=${2:-}
version=${3:-}
base=${4:-}
engine=$(scripts/engine.sh)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if "$engine" image inspect "$ref" >/dev/null 2>&1; then
	"$engine" save -o "$work/image.tar" "$ref" >/dev/null
	target=(--input "$work/image.tar")
else
	target=("$ref")
fi

vex=(--vex vex/libre-devops.openvex.json)
if [ -n "$image" ]; then
	uv run --quiet scripts/images.py vex "$image" "$version" --base "$base" --output "$work/base.openvex.json"
	vex+=(--vex "$work/base.openvex.json")
fi

report=${SCAN_REPORT:-$work/report.json}
trivy image --quiet --scanners vuln --show-suppressed --ignorefile .trivyignore.yaml "${vex[@]}" \
	--format json --output "$report" "${target[@]}"
trivy convert --quiet --format table --severity HIGH,CRITICAL "$report"

suppressed=$(jq '[.Results[]? | .ExperimentalModifiedFindings[]?] | length' "$report")
echo "scan: $suppressed finding(s) set aside by VEX statements (listed in the JSON report)"

# shellcheck disable=SC2016 # a jq program, expanded by jq
blocking='[.Results[]? | .Target as $target | .Vulnerabilities[]?
  | select(.Severity == "CRITICAL" or (.Severity == "HIGH" and (.FixedVersion // "") != ""))
  | "\(.Severity)  \(.VulnerabilityID)  \(.PkgName) \(.InstalledVersion) (fixed in \(.FixedVersion // "no release"))  \($target)"]'
count=$(jq "$blocking | length" "$report")
if [ "$count" -gt 0 ]; then
	echo "scan: $count finding(s) block this image:" >&2
	jq -r "$blocking | .[]" "$report" >&2
	exit 1
fi
echo "scan: $ref passes (no critical findings, no high findings with a fix available)"
