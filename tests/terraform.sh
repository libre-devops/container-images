# Smoke tests for the terraform image.
# shellcheck shell=bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

tenv --version
terraform version
tflint --version
terraform-docs --version
conftest --version

[ "$(terraform version -json | jq -r .terraform_version)" = "$EXPECT_TERRAFORM" ] ||
	fail "the default Terraform is not $EXPECT_TERRAFORM"
ok "default Terraform $EXPECT_TERRAFORM"

# Match against captured output: `cmd | grep -q` fails under pipefail when
# grep exits early and cmd gets SIGPIPE.
grep -q "v$EXPECT_TENV" <<<"$(tenv --version)" || fail "tenv is not $EXPECT_TENV"
grep -q "version $EXPECT_TFLINT" <<<"$(tflint --version)" || fail "TFLint is not $EXPECT_TFLINT"
grep -q "v$EXPECT_TERRAFORM_DOCS" <<<"$(terraform-docs --version)" || fail "terraform-docs is not $EXPECT_TERRAFORM_DOCS"
grep -q "Conftest: $EXPECT_CONFTEST" <<<"$(conftest --version)" || fail "Conftest is not $EXPECT_CONFTEST"
ok "tenv $EXPECT_TENV, TFLint $EXPECT_TFLINT, terraform-docs $EXPECT_TERRAFORM_DOCS, Conftest $EXPECT_CONFTEST"

# A repository's .terraform-version wins, and tenv installs it as the app user.
other=1.9.8
cd "$(mktemp -d)"
echo "$other" >.terraform-version
[ "$(terraform version -json | jq -r .terraform_version)" = "$other" ] ||
	fail ".terraform-version did not select Terraform $other"
ok ".terraform-version selects Terraform $other, installed on demand"
