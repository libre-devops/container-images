#!/usr/bin/env bash
# start-gitlab-runner: runs this container as a GitLab Runner with the shell
# executor, so jobs run here, in this container, as the app user. By default
# it runs one job and exits, so every job gets a fresh container.
#
# Create the runner in GitLab first (a project's, group's or the instance's
# CI/CD settings, or the API), with its tags, and pass its runner
# authentication token (glrt-...). One token serves any number of containers:
# each shows in GitLab as one of the runner's managers, and nothing needs
# removing when a container exits.
#
# Required:
#   GITLAB_URL                The GitLab instance, such as https://gitlab.com
#   GITLAB_RUNNER_TOKEN       The runner authentication token; or
#                             GITLAB_RUNNER_TOKEN_FILE, the path of a file
#                             holding it (a mounted secret), which keeps it
#                             out of the environment.
# Optional:
#   GITLAB_RUNNER_NAME        The name in job logs (default:
#                             gitlab-runner-<ddmmyyyyhhmmss>-<4 random hex digits>)
#   GITLAB_RUNNER_EPHEMERAL   true (default): one job, then exit. false: keep
#                             running jobs until stopped.
# Anything else run-single supports comes from GitLab Runner's own environment
# variables, such as RUNNER_SHELL=pwsh or RUNNER_BUILDS_DIR.
#
# Builds and the cache go in /opt/gitlab-runner. Jobs run as the same user as
# the runner, so they could read its token, which lets its holder take the
# runner's jobs: use one runner per trust boundary.

set -euo pipefail

die() {
	echo "start-gitlab-runner: $*" >&2
	exit 1
}

[ -n "${GITLAB_URL:-}" ] || die "set GITLAB_URL to the GitLab instance, such as https://gitlab.com"
if [ -n "${GITLAB_RUNNER_TOKEN_FILE:-}" ]; then
	[ -r "$GITLAB_RUNNER_TOKEN_FILE" ] || die "cannot read GITLAB_RUNNER_TOKEN_FILE ($GITLAB_RUNNER_TOKEN_FILE)"
	token=$(<"$GITLAB_RUNNER_TOKEN_FILE")
elif [ -n "${GITLAB_RUNNER_TOKEN:-}" ]; then
	token=$GITLAB_RUNNER_TOKEN
else
	die "set GITLAB_RUNNER_TOKEN (the runner authentication token, glrt-...), or GITLAB_RUNNER_TOKEN_FILE"
fi
case $token in
GR1348941*) die "that is a registration token, which cannot take jobs: create a runner in GitLab and use its authentication token (glrt-...)" ;;
esac

case ${GITLAB_RUNNER_EPHEMERAL:-true} in
true) once=(--max-builds 1) ;;
false) once=() ;;
*) die "GITLAB_RUNNER_EPHEMERAL must be true or false, not '$GITLAB_RUNNER_EPHEMERAL'" ;;
esac

# Unique by default: containers started in the same second (a scaled
# Deployment) still get different names.
name=${GITLAB_RUNNER_NAME:-gitlab-runner-$(date -u +%d%m%Y%H%M%S)-$(printf '%04x' "$RANDOM")}

# The shell executor hands its own environment to every job, so the token
# goes to the runner as an argument and leaves the environment here.
unset GITLAB_RUNNER_TOKEN GITLAB_RUNNER_TOKEN_FILE CI_SERVER_TOKEN

cd /opt/gitlab-runner
exec gitlab-runner run-single \
	--url "$GITLAB_URL" \
	--token "$token" \
	--name "$name" \
	--executor shell \
	"${once[@]}"
