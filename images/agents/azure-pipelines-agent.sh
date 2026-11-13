#!/usr/bin/env bash
# start-agent: registers this container as a self-hosted Azure Pipelines agent
# and runs jobs. By default it runs one job, removes its registration and
# exits, so every job gets a fresh container.
#
# Required:
#   AZP_URL          The organisation URL, such as https://dev.azure.com/contoso
#   AZP_TOKEN        A personal access token with the Agent Pools (Read & manage)
#                    scope; or AZP_TOKEN_FILE, the path of a file holding one
#                    (a mounted secret), which keeps it out of the environment.
# Optional:
#   AZP_POOL         The agent pool (default: Default)
#   AZP_AGENT_NAME   The agent's name (default: the container's hostname)
#   AZP_WORK         The work directory (default: _work in the agent directory)
#   AZP_EPHEMERAL    true (default): one job, then deregister and exit.
#                    false: keep running jobs until stopped, then deregister.
#
# Jobs run as the same user as the agent, so they could read a token the
# agent holds: give it only the Agent Pools scope.

set -euo pipefail

agent=/opt/azure-pipelines-agent

die() {
	echo "start-agent: $*" >&2
	exit 1
}

[ -n "${AZP_URL:-}" ] || die "set AZP_URL to the organisation URL, such as https://dev.azure.com/contoso"
if [ -n "${AZP_TOKEN_FILE:-}" ]; then
	[ -r "$AZP_TOKEN_FILE" ] || die "cannot read AZP_TOKEN_FILE ($AZP_TOKEN_FILE)"
	token=$(<"$AZP_TOKEN_FILE")
elif [ -n "${AZP_TOKEN:-}" ]; then
	token=$AZP_TOKEN
else
	die "set AZP_TOKEN (a personal access token with the Agent Pools (Read & manage) scope), or AZP_TOKEN_FILE"
fi
unset AZP_TOKEN
case ${AZP_EPHEMERAL:-true} in
true) once=(--once) ;;
false) once=() ;;
*) die "AZP_EPHEMERAL must be true or false, not '$AZP_EPHEMERAL'" ;;
esac

# The agent reports its environment to Azure DevOps as capabilities; keep the
# token's variables out of that list.
export VSO_AGENT_IGNORE="AZP_TOKEN,AZP_TOKEN_FILE${VSO_AGENT_IGNORE:+,$VSO_AGENT_IGNORE}"

cd "$agent"
./config.sh --unattended \
	--url "$AZP_URL" \
	--auth pat --token "$token" \
	--pool "${AZP_POOL:-Default}" \
	--agent "${AZP_AGENT_NAME:-$HOSTNAME}" \
	--work "${AZP_WORK:-_work}" \
	--replace \
	--acceptTeeEula

deregister() {
	trap - EXIT
	echo "start-agent: removing the registration"
	./config.sh remove --unattended --auth pat --token "$token" || true
}
trap deregister EXIT

./run.sh "${once[@]}" &
pid=$!
trap 'kill -TERM "$pid" 2>/dev/null || true; wait "$pid" || true; exit 143' TERM INT
wait "$pid"
