#!/bin/sh
# Installs ansible-core, ansible-lint and their libraries into their own
# virtual environment at /opt/ansible from a hash-locked requirements file
# (written by `just lock`, with any dependency that has a known vulnerability
# raised to its fixed version), and puts the ansible commands on PATH. Given a
# directory of collection tarballs, already checked against their pinned
# SHA-256 by fetch-tool.sh, it also installs those collections for all users.
#
# Usage: install.sh <uv> <lock> [collection directory]
# Reads PYTHON_MINOR from the environment.

set -eu

die() {
	printf 'ansible install: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || die "usage: install.sh <uv> <lock> [collection directory]"
uv=$1
lock=$2
collections=${3:-}
: "${PYTHON_MINOR:?}"
[ -f "$lock" ] || die "no lock at $lock; run just lock"

export UV_NO_CACHE=1 UV_PYTHON_DOWNLOADS=never
python=$(command -v "python$PYTHON_MINOR")

"$uv" venv --python "$python" /opt/ansible
"$uv" pip install --python /opt/ansible/bin/python --require-hashes --no-deps -r "$lock"

# Each script's shebang names the virtual environment's Python, so symlinks
# on PATH run the right interpreter.
for command in /opt/ansible/bin/ansible /opt/ansible/bin/ansible-*; do
	ln -sf "$command" "/usr/local/bin/${command##*/}"
done

if [ -n "$collections" ]; then
	set -- "$collections"/*.tar.gz
	[ -f "$1" ] || die "no collection tarballs in $collections"
	for tarball in "$@"; do
		/opt/ansible/bin/ansible-galaxy collection install --offline --no-deps \
			--collections-path /usr/share/ansible/collections "$tarball"
	done
fi
