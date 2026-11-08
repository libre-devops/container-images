# Shared smoke tests, run in every image as its default user.
# shellcheck shell=bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

[ "$(id -u)" = 10001 ] || fail "id -u is $(id -u), want 10001"
[ "$(id -g)" = 10001 ] || fail "id -g is $(id -g), want 10001"
ok "runs as uid and gid 10001 ($(id -un))"

[ "$PWD" = /work ] || fail "working directory is $PWD, want /work"
[ "$HOME" = /home/app ] || fail "HOME is $HOME, want /home/app"
touch "$HOME/.write-test" /work/.write-test
rm -f "$HOME/.write-test" /work/.write-test
ok "HOME and /work are writable"

for tool in bash git curl jq shellcheck shfmt; do
	command -v "$tool" >/dev/null || fail "$tool is not on PATH"
done
bash --version | sed -n 1p
git --version
curl --version | sed -n 1p

[ "$(jq --version)" = "jq-$EXPECT_JQ" ] || fail "jq is $(jq --version), want $EXPECT_JQ"
grep -qx "version: $EXPECT_SHELLCHECK" <<<"$(shellcheck --version)" || fail "ShellCheck is not $EXPECT_SHELLCHECK"
[ "$(shfmt --version)" = "v$EXPECT_SHFMT" ] || fail "shfmt is $(shfmt --version), want $EXPECT_SHFMT"
ok "jq $EXPECT_JQ, ShellCheck $EXPECT_SHELLCHECK and shfmt $EXPECT_SHFMT"

# shellcheck disable=SC2016 # the script under test, written literally
printf '#!/bin/sh\necho "$1"\n' >/tmp/check.sh
shellcheck /tmp/check.sh
shfmt -d /tmp/check.sh
ok "ShellCheck and shfmt run"

curl -fsS -o /dev/null https://github.com
git ls-remote https://github.com/libre-devops/container-images HEAD >/dev/null
ok "TLS works against the image's CA bundle (curl and git)"

command -v update-ca-certificates >/dev/null || command -v update-ca-trust >/dev/null ||
	fail "neither update-ca-certificates nor update-ca-trust is available for adding a CA"
ok "CA tooling is present"

musl=false
for loader in /lib/ld-musl-*.so.1; do
	[ -e "$loader" ] && musl=true
done
if $musl; then
	ok "musl base: useradd is not required (Azure Pipelines container jobs need glibc)"
else
	command -v useradd >/dev/null || fail "useradd is missing (Azure Pipelines container jobs need it)"
	ok "useradd is present for Azure Pipelines container jobs"
fi
