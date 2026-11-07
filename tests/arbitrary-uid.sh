# Run as an arbitrary uid in group 0, as OpenShift and GitHub Actions
# container jobs (`--user 1001:0`) do.
# shellcheck shell=bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ "$(id -u)" = 4242 ] || fail "expected uid 4242, got $(id -u)"
[ "$HOME" = /home/app ] || fail "HOME is $HOME, want /home/app"
touch "$HOME/.write-test" /work/.write-test || fail "HOME or /work is not writable by group 0"
rm -f "$HOME/.write-test" /work/.write-test
git --version >/dev/null
echo "ok: uid 4242 (group 0) can write to HOME and /work"
