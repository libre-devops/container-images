#!/bin/sh
# Installs ansible-core, ansible-lint and their libraries into their own
# virtual environment at /opt/ansible from a hash-locked requirements file
# (written by `just lock`, with any dependency that has a known vulnerability
# raised to its fixed version), and puts the ansible commands, Molecule's,
# yamllint's (which ansible-lint brings) and pytest's (where the lock has it)
# on PATH. Given the fetch stage's
# directory, it also installs, for all users, every collection tarball the
# build fetched there (<fetched>/<collection>/collections), each already
# checked against its pinned SHA-256 by fetch-tool.sh.
#
# Usage: install.sh <uv> <lock> [fetched directory]
# Reads PYTHON_MINOR from the environment.

set -eu

die() {
	printf 'ansible install: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || die "usage: install.sh <uv> <lock> [fetched directory]"
uv=$1
lock=$2
fetched=${3:-}
: "${PYTHON_MINOR:?}"
[ -f "$lock" ] || die "no lock at $lock; run just lock"

export UV_NO_CACHE=1 UV_PYTHON_DOWNLOADS=never
python=$(command -v "python$PYTHON_MINOR")

"$uv" venv --python "$python" /opt/ansible
"$uv" pip install --python /opt/ansible/bin/python --require-hashes --no-deps -r "$lock"

# Each script's shebang names the virtual environment's Python, so symlinks
# on PATH run the right interpreter.
for command in /opt/ansible/bin/ansible /opt/ansible/bin/ansible-* /opt/ansible/bin/molecule /opt/ansible/bin/yamllint \
	/opt/ansible/bin/pytest; do
	[ -e "$command" ] || continue
	ln -sf "$command" "/usr/local/bin/${command##*/}"
done

if [ -n "$fetched" ]; then
	found=
	for tarball in "$fetched"/*/collections/*.tar.gz; do
		[ -f "$tarball" ] || break
		found=1
		/opt/ansible/bin/ansible-galaxy collection install --offline --no-deps \
			--collections-path /usr/share/ansible/collections "$tarball"
	done
	[ -n "$found" ] || die "no collection tarballs under $fetched"
fi
