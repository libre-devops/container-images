#!/bin/sh
# Installs the Azure CLI into its own virtual environment at /opt/az, and
# ldo-cli into another at /opt/ldo-cli, from hash-locked requirements.
#
# The locks (images/locks/, written by `just lock`) pin every dependency by
# version and SHA-256, with any dependency that has a known vulnerability
# raised to its fixed version. ldo-cli itself comes from its release wheel,
# already checked against its pinned SHA-256 by fetch-tool.sh.
#
# Usage: install.sh <uv> <azure-cli lock> <ldo-cli lock> <ldo-cli wheel directory>
# Reads PYTHON_MINOR from the environment.

set -eu

die() {
	printf 'azure-cli install: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 4 ] || die "usage: install.sh <uv> <azure-cli lock> <ldo-cli lock> <wheel directory>"
uv=$1
az_lock=$2
ldo_lock=$3
wheels=$4
: "${PYTHON_MINOR:?}"
[ -f "$az_lock" ] || die "no lock at $az_lock; run just lock"
[ -f "$ldo_lock" ] || die "no lock at $ldo_lock; run just lock"

export UV_NO_CACHE=1 UV_PYTHON_DOWNLOADS=never
python=$(command -v "python$PYTHON_MINOR")

# --seed adds pip, which `az extension add` needs.
"$uv" venv --seed --python "$python" /opt/az
"$uv" pip install --python /opt/az/bin/python --require-hashes --no-deps -r "$az_lock"

# The az script in the virtual environment finds its Python relative to its
# own path, so a symlink elsewhere would run the wrong interpreter.
cat >/usr/local/bin/az <<'EOF'
#!/bin/sh
exec /opt/az/bin/python -Im azure.cli "$@"
EOF
chmod 0755 /usr/local/bin/az

set -- "$wheels"/*.whl
[ "$#" -eq 1 ] && [ -f "$1" ] || die "expected exactly one ldo-cli wheel in $wheels"
"$uv" venv --python "$python" /opt/ldo-cli
"$uv" pip install --python /opt/ldo-cli/bin/python --require-hashes --no-deps -r "$ldo_lock"
"$uv" pip install --python /opt/ldo-cli/bin/python --no-deps "$1"
ln -sf /opt/ldo-cli/bin/ldo /usr/local/bin/ldo
