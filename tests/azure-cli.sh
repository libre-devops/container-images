# Smoke tests for the azure-cli image.
# shellcheck shell=bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

az version
[ "$(az version --output json | jq -r '."azure-cli"')" = "$EXPECT_AZURE_CLI" ] ||
	fail "az reports a version other than $EXPECT_AZURE_CLI"
ok "Azure CLI $EXPECT_AZURE_CLI"

got=$(/opt/az/bin/python -c 'import sys; print("%d.%d" % sys.version_info[:2])')
[ "$got" = "$EXPECT_PYTHON" ] || fail "the Azure CLI runs on CPython $got, want $EXPECT_PYTHON"
ok "the Azure CLI runs on CPython $EXPECT_PYTHON"

/opt/az/bin/python -m pip --version >/dev/null || fail "pip is missing, so az extension add would fail"
ok "pip is available for az extensions"

# Load real command modules and the libraries `just lock` may have raised for
# security fixes, so an override that breaks the CLI fails here.
az group --help >/dev/null
az vm --help >/dev/null
az storage account --help >/dev/null
/opt/az/bin/python -c 'import cryptography, msal, azure.mgmt.resource; from cryptography.hazmat.primitives.asymmetric import rsa; rsa.generate_private_key(public_exponent=65537, key_size=2048); print("cryptography", cryptography.__version__)'
/opt/az/bin/python -c 'import paramiko; print("paramiko", paramiko.__version__)' 2>/dev/null || true
az config set core.only_show_errors=true >/dev/null
ok "the Azure CLI loads its command modules and patched libraries"

ldo --help >/dev/null
got=$(/opt/ldo-cli/bin/python -c 'import importlib.metadata as m; print(m.version("libre-devops-helpers"))')
[ "$got" = "$EXPECT_LDO_CLI" ] || fail "ldo-cli is $got, want $EXPECT_LDO_CLI"
ok "ldo-cli $EXPECT_LDO_CLI"
