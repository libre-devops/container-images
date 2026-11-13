#!/usr/bin/env bash
# start-runner: registers this container as a self-hosted GitHub Actions
# runner and runs jobs. By default the runner is ephemeral: it runs one job,
# GitHub removes it, and the container exits, so every job gets a fresh one.
#
# One of:
#   RUNNER_JIT_CONFIG    A just-in-time configuration from the REST API
#                        (generate-jitconfig). Needs nothing else, and is
#                        always ephemeral.
#   RUNNER_URL and RUNNER_TOKEN
#                        Where to register (https://github.com/<org>,
#                        https://github.com/<owner>/<repo>, or the same on a
#                        GitHub Enterprise Server host) and a registration
#                        token for it.
#   RUNNER_URL and RUNNER_ACCESS_TOKEN
#                        As above, with a token that can create registration
#                        tokens (a GitHub App installation token or a
#                        fine-grained personal access token: Administration
#                        write on a repository, or Self-hosted runners write
#                        on an organisation).
# Optional:
#   RUNNER_NAME          The runner's name (default: the container's hostname)
#   RUNNER_LABELS        Extra labels, comma-separated
#   RUNNER_GROUP         The runner group (organisations)
#   RUNNER_WORKDIR       The work directory (default: _work in the runner directory)
#   RUNNER_EPHEMERAL     true (default): one job. false: keep running jobs
#                        until stopped (with RUNNER_ACCESS_TOKEN, the runner
#                        then removes its registration).
#
# The runner never updates itself (--disableupdate): new versions arrive as new
# images, and GitHub stops sending jobs to a runner 30 days after a newer
# release, so keep pulling the moving tags.

set -euo pipefail

runner=/opt/actions-runner

die() {
	echo "start-runner: $*" >&2
	exit 1
}

cd "$runner"

if [ -n "${RUNNER_JIT_CONFIG:-}" ]; then
	jit=$RUNNER_JIT_CONFIG
	unset RUNNER_JIT_CONFIG RUNNER_TOKEN RUNNER_ACCESS_TOKEN
	exec ./run.sh --jitconfig "$jit"
fi

[ -n "${RUNNER_URL:-}" ] || die "set RUNNER_URL (https://github.com/<org> or https://github.com/<owner>/<repo>) and RUNNER_TOKEN or RUNNER_ACCESS_TOKEN, or set RUNNER_JIT_CONFIG"
access=${RUNNER_ACCESS_TOKEN:-}
registration=${RUNNER_TOKEN:-}
unset RUNNER_TOKEN RUNNER_ACCESS_TOKEN
[ -n "$registration" ] || [ -n "$access" ] || die "set RUNNER_TOKEN (a registration token) or RUNNER_ACCESS_TOKEN"

case ${RUNNER_EPHEMERAL:-true} in
true) ephemeral=true ;;
false) ephemeral=false ;;
*) die "RUNNER_EPHEMERAL must be true or false, not '$RUNNER_EPHEMERAL'" ;;
esac

# token <registration-token|remove-token>: asks the REST API for one, for the
# repository, organisation or enterprise that RUNNER_URL names.
token() {
	local rest host path scope api
	rest=${RUNNER_URL#https://}
	host=${rest%%/*}
	path=${rest#*/}
	path=${path%/}
	case $path in
	enterprises/*) scope=$path ;;
	*/*) scope=repos/$path ;;
	*) scope=orgs/$path ;;
	esac
	if [ "$host" = github.com ]; then
		api=https://api.github.com
	else
		api=https://$host/api/v3
	fi
	curl -fsS -X POST \
		-H "Authorization: Bearer $access" \
		-H "Accept: application/vnd.github+json" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		"$api/$scope/actions/runners/$1" | jq -er .token
}

if [ -z "$registration" ]; then
	registration=$(token registration-token) || die "could not get a registration token for $RUNNER_URL with RUNNER_ACCESS_TOKEN"
fi

args=(--unattended --url "$RUNNER_URL" --token "$registration"
	--name "${RUNNER_NAME:-$HOSTNAME}" --work "${RUNNER_WORKDIR:-_work}"
	--replace --disableupdate)
[ -n "${RUNNER_LABELS:-}" ] && args+=(--labels "$RUNNER_LABELS")
[ -n "${RUNNER_GROUP:-}" ] && args+=(--runnergroup "$RUNNER_GROUP")
$ephemeral && args+=(--ephemeral)
./config.sh "${args[@]}"
unset registration

if $ephemeral || [ -z "$access" ]; then
	unset access
	exec ./run.sh
fi

deregister() {
	trap - EXIT
	echo "start-runner: removing the registration"
	local removal
	removal=$(token remove-token) && ./config.sh remove --token "$removal" || true
}
trap deregister EXIT
./run.sh &
pid=$!
trap 'kill -TERM "$pid" 2>/dev/null || true; wait "$pid" || true; exit 143' TERM INT
wait "$pid"
