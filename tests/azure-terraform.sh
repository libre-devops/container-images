# Smoke tests for the azure-terraform image: every mirrored provider version
# installs with no registry, and the registry configuration still works.
# shellcheck shell=bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

[ "$(tfstacks --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)" = "$EXPECT_TFSTACKS" ] ||
	fail "tfstacks is not $EXPECT_TFSTACKS: $(tfstacks --version)"
ok "tfstacks $EXPECT_TFSTACKS"

[ "$TF_CLI_CONFIG_FILE" = /usr/local/share/terraform/airgapped.tfrc ] || fail "TF_CLI_CONFIG_FILE is $TF_CLI_CONFIG_FILE"

# The nth version of every provider, in one configuration.
declare -A versions
for pair in $EXPECT_TERRAFORM_PROVIDERS; do
	versions[${pair%%=*}]=${pair#*=}
done
for n in 1 2 3; do
	dir=$(mktemp -d)
	{
		echo 'terraform {'
		echo '  required_providers {'
		for source in "${!versions[@]}"; do
			version=$(cut -d , -f "$n" <<<"${versions[$source]}")
			[ -n "$version" ] || continue
			echo "    ${source#*/} = { source = \"$source\", version = \"$version\" }"
		done
		echo '  }'
		echo '}'
	} >"$dir/main.tf"
	# Any request to the registry fails: the proxy does not exist.
	out=$(cd "$dir" && HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 terraform init -input=false -backend=false -no-color 2>&1) || {
		echo "$out" >&2
		fail "terraform init needed the registry for release $n of the mirrored providers"
	}
	for source in "${!versions[@]}"; do
		version=$(cut -d , -f "$n" <<<"${versions[$source]}")
		[ -n "$version" ] || continue
		grep -q "Installed $source v$version" <<<"$out" || {
			echo "$out" >&2
			fail "$source $version did not install from the mirror"
		}
	done
	rm -rf "$dir"
done
ok "every mirrored provider version installs with no registry: $EXPECT_TERRAFORM_PROVIDERS"

dir=$(mktemp -d)
printf 'terraform {\n  required_providers {\n    msgraph = { source = "microsoft/msgraph", version = "0.3.0" }\n  }\n}\n' >"$dir/main.tf"
out=$(cd "$dir" && TF_CLI_CONFIG_FILE=/usr/local/share/terraform/registry.tfrc terraform init -input=false -backend=false -no-color 2>&1) || {
	echo "$out" >&2
	fail "the registry configuration could not install a provider version the mirror lacks"
}
ok "the registry configuration installs a version the mirror lacks"
