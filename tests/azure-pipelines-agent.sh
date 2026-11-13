# Smoke tests for the azure-pipelines-agent image.
# shellcheck shell=bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

agent=/opt/azure-pipelines-agent
got=$("$agent/bin/Agent.Listener" --version)
[ "$got" = "$EXPECT_AZURE_PIPELINES_AGENT" ] || fail "the agent is $got, want $EXPECT_AZURE_PIPELINES_AGENT"
ok "Azure Pipelines agent $EXPECT_AZURE_PIPELINES_AGENT (.NET, ICU and OpenSSL load)"

touch "$agent/.write-test" && rm "$agent/.write-test"
ok "the agent directory is writable"

# The *_alpine builds are musl binaries the agent mounts into Alpine
# container jobs; they do not run here.
for node in "$agent"/externals/node*/bin/node; do
	[ -x "$node" ] || continue
	case $node in */node*_alpine/*) continue ;; esac
	"$node" --version >/dev/null || fail "$node does not run"
done
ok "the agent's Node runtimes run"

out=$(start-agent 2>&1) && fail "start-agent succeeded with no settings"
grep -q AZP_URL <<<"$out" || fail "start-agent did not explain what to set: $out"
out=$(AZP_URL=https://dev.azure.com/example start-agent 2>&1) && fail "start-agent succeeded with no token"
grep -q AZP_TOKEN <<<"$out" || fail "start-agent did not ask for a token: $out"
ok "start-agent explains the settings it needs"
