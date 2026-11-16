#!/bin/sh
# Installs ansible-core, ansible-lint and their libraries into their own
# virtual environment at /opt/ansible from a hash-locked requirements file
# (written by `just lock`, with any dependency that has a known vulnerability
# raised to its fixed version), and puts the ansible commands (and Molecule's)
# on PATH. Given directories of collection tarballs, already checked against
# their pinned SHA-256 by fetch-tool.sh, it also installs those collections
# for all users.
#
# Usage: install.sh <uv> <lock> [collection directory...]
# Reads PYTHON_MINOR from the environment.

set -eu

die() {
	printf 'ansible install: %s\n' "$*" >&2
	exit 1
}

[ "$#" -ge 2 ] || die "usage: install.sh <uv> <lock> [collection directory...]"
uv=$1
lock=$2
shift 2
: "${PYTHON_MINOR:?}"
[ -f "$lock" ] || die "no lock at $lock; run just lock"

export UV_NO_CACHE=1 UV_PYTHON_DOWNLOADS=never
python=$(command -v "python$PYTHON_MINOR")

"$uv" venv --python "$python" /opt/ansible
"$uv" pip install --python /opt/ansible/bin/python --require-hashes --no-deps -r "$lock"

# Each script's shebang names the virtual environment's Python, so symlinks
# on PATH run the right interpreter.
for command in /opt/ansible/bin/ansible /opt/ansible/bin/ansible-* /opt/ansible/bin/molecule; do
	ln -sf "$command" "/usr/local/bin/${command##*/}"
done

for collections in "$@"; do
	found=
	for tarball in "$collections"/*.tar.gz; do
		[ -f "$tarball" ] || break
		found=1
		/opt/ansible/bin/ansible-galaxy collection install --offline --no-deps \
			--collections-path /usr/share/ansible/collections "$tarball"
	done
	[ -n "$found" ] || die "no collection tarballs in $collections"
done
