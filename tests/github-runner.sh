# Smoke tests for the github-runner image.
# shellcheck shell=bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

runner=/opt/actions-runner
got=$("$runner/bin/Runner.Listener" --version)
[ "$got" = "$EXPECT_GITHUB_RUNNER" ] || fail "the runner is $got, want $EXPECT_GITHUB_RUNNER"
ok "GitHub Actions runner $EXPECT_GITHUB_RUNNER (.NET, ICU and OpenSSL load)"

touch "$runner/.write-test" && rm "$runner/.write-test"
ok "the runner directory is writable"

# The *_alpine builds are musl binaries the agent mounts into Alpine
# container jobs; they do not run here.
for node in "$runner"/externals/node*/bin/node; do
	[ -x "$node" ] || continue
	case $node in */node*_alpine/*) continue ;; esac
	"$node" --version >/dev/null || fail "$node does not run"
	[ ! -e "${node%/node}/npm" ] || fail "${node%/node}/npm is still there"
done
ok "the runner's Node runtimes run, without npm"

out=$(start-runner 2>&1) && fail "start-runner succeeded with no settings"
grep -q RUNNER_URL <<<"$out" || fail "start-runner did not explain what to set: $out"
out=$(RUNNER_URL=https://github.com/example start-runner 2>&1) && fail "start-runner succeeded with no token"
grep -q RUNNER_TOKEN <<<"$out" || fail "start-runner did not ask for a token: $out"
ok "start-runner explains the settings it needs"
