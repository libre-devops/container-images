# Smoke tests for the ansible-azure image: the collection, and every Python
# library its modules import.
# shellcheck shell=bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

got=$(ansible-galaxy collection list azure.azcollection --format json |
	jq -r '[.[] | ."azure.azcollection".version] | first')
[ "$got" = "$EXPECT_ANSIBLE_AZURE" ] || fail "azure.azcollection is $got, want $EXPECT_ANSIBLE_AZURE"
ok "azure.azcollection $EXPECT_ANSIBLE_AZURE"

ansible-doc azure.azcollection.azure_rm_resourcegroup >/dev/null
ok "ansible-doc reads its modules"

# With no credentials, a module gets as far as authenticating, which it only
# reaches after importing every library it needs.
cd "$(mktemp -d)"
out=$(ansible localhost -c local -m azure.azcollection.azure_rm_resourcegroup_info -a name=smoke-test 2>&1 || true)
if grep -qiE 'Failed to import|No module named|requires the .* Python' <<<"$out"; then
	echo "$out" >&2
	fail "an Azure module is missing a Python library"
fi
grep -qi 'credentials' <<<"$out" || {
	echo "$out" >&2
	fail "expected the Azure module to stop at authentication"
}
ok "the Azure modules import their libraries and stop at authentication"
