#!/usr/bin/env bash
# Lints the repository as early as possible, before anything is built:
#   - the Containerfile (hadolint),
#   - shell scripts (ShellCheck and shfmt),
#   - GitHub Actions workflows, for correctness (actionlint) and for security
#     (zizmor: template injection, excessive permissions, unpinned actions,
#     credential persistence and more),
#   - the repository itself for leaked secrets and misconfigurations (Trivy),
#   - the text rules (no en or em dashes anywhere).
#
# Usage: scripts/lint.sh   (tools come from scripts/ci-tools.sh)

set -euo pipefail

cd "$(dirname "$0")/.."
status=0

echo "== hadolint"
hadolint images/Containerfile || status=1

mapfile -t scripts < <(git ls-files --cached --others --exclude-standard '*.sh')
echo "== ShellCheck (${#scripts[@]} scripts)"
shellcheck --external-sources "${scripts[@]}" || status=1

echo "== shfmt"
shfmt --diff "${scripts[@]}" || status=1

echo "== actionlint"
actionlint || status=1

echo "== zizmor"
zizmor --persona=regular --min-severity=low .github/workflows || status=1

echo "== Trivy: secrets and misconfigurations in the repository"
trivy fs --quiet --scanners secret,misconfig --severity MEDIUM,HIGH,CRITICAL \
	--skip-dirs .tools --exit-code 1 . || status=1

echo "== no en or em dashes"
en=$(printf '\342\200\223')
em=$(printf '\342\200\224')
if git ls-files --cached --others --exclude-standard -z |
	xargs -0 grep -n -I -F -e "$en" -e "$em" --; then
	echo "lint: replace the dashes above with commas, colons, brackets or full stops" >&2
	status=1
fi

exit "$status"
