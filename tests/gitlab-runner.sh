# Smoke tests for the gitlab-runner image.
# shellcheck shell=bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

out=$(gitlab-runner --version)
got=$(awk '$1 == "Version:" { print $2 }' <<<"$out")
[ "$got" = "$EXPECT_GITLAB_RUNNER" ] || fail "the runner is $got, want $EXPECT_GITLAB_RUNNER: $out"
ok "GitLab Runner $EXPECT_GITLAB_RUNNER"

# start-gitlab-runner relies on these run-single flags.
help=$(gitlab-runner run-single --help 2>&1)
for flag in --url --token --name --executor --max-builds; do
	grep -q -- "$flag" <<<"$help" || fail "run-single has no $flag flag"
done
ok "run-single takes the flags start-gitlab-runner passes"

touch /opt/gitlab-runner/.write-test && rm /opt/gitlab-runner/.write-test
ok "the runner directory is writable"

# The shell executor runs each job in a bash login shell, which reads
# /etc/profile: the tools must still be on its PATH there.
login=$(bash -l -c 'command -v gitlab-runner git curl')
[ "$(wc -l <<<"$login")" -eq 3 ] || fail "a login shell does not find gitlab-runner, git and curl: $login"
ok "jobs' login shells find gitlab-runner, git and curl"

out=$(start-gitlab-runner 2>&1) && fail "start-gitlab-runner succeeded with no settings"
grep -q GITLAB_URL <<<"$out" || fail "start-gitlab-runner did not explain what to set: $out"
out=$(GITLAB_URL=https://gitlab.example.com start-gitlab-runner 2>&1) && fail "start-gitlab-runner succeeded with no token"
grep -q GITLAB_RUNNER_TOKEN <<<"$out" || fail "start-gitlab-runner did not ask for a token: $out"
out=$(GITLAB_URL=https://gitlab.example.com GITLAB_RUNNER_TOKEN=GR1348941example start-gitlab-runner 2>&1) &&
	fail "start-gitlab-runner accepted a registration token"
grep -q "registration token" <<<"$out" || fail "start-gitlab-runner did not explain the registration token: $out"
ok "start-gitlab-runner explains the settings it needs"
