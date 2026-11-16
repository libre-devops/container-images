#!/bin/sh
# Fetches every pinned download a build asked for, each into its own root
# under <dir> so that later stages copy exactly the ones they need:
# <dir>/common (ShellCheck and jq, in every image), <dir>/uv, <dir>/ldo-cli,
# <dir>/powershell, the Ansible collections (<dir>/<collection>/collections)
# and the CI agents. A download is asked for by setting its <TOOL>_ASSET build
# argument; the others are skipped. ANSIBLE_ROLES, when set, fetches Galaxy
# roles into <dir>/ansible-roles (see images/ansible/fetch-roles.sh).
#
# Usage: fetch-all.sh <dir>

set -eu

dir=${1:?usage: fetch-all.sh <dir>}
lib=$(dirname "$0")

sh "$lib/fetch-tool.sh" "$dir/common" shellcheck "${SHELLCHECK_ASSET:?}"
sh "$lib/fetch-tool.sh" "$dir/common" jq "${JQ_ASSET:?}"
for tool in uv ldo-cli powershell azure-azcollection containers-podman community-general ansible-posix theforeman-foreman \
	just azure-pipelines-agent github-runner gitlab-runner; do
	var=$(echo "$tool" | tr 'a-z-' 'A-Z_')_ASSET
	eval "spec=\${$var:-}"
	if [ -n "$spec" ]; then
		sh "$lib/fetch-tool.sh" "$dir/$tool" "$tool" "$spec"
	fi
done
if [ -n "${ANSIBLE_ROLES:-}" ]; then
	sh "$lib/../ansible/fetch-roles.sh" "$dir/ansible-roles"
fi
