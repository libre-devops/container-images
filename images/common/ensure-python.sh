#!/bin/sh
# Makes python<major.minor>, python3 and python on PATH the requested CPython.
#
# A base that already ships that version (the Docker Hardened Images Python
# bases, or RHEL's python3.12) is used as it is. Any other base gets CPython
# from uv, whose pinned release fixes the exact python-build-standalone build
# and verifies its hash, so the same Containerfile works on Debian, RHEL or
# Wolfi.
#
# Usage: ensure-python.sh <major.minor> <path to uv>

set -eu

die() {
	printf 'ensure-python: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 2 ] || die "usage: ensure-python.sh <major.minor> <path to uv>"
want=$1
uv=$2

minor_of() {
	"$1" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true
}

found=
for name in "python$want" python3; do
	path=$(command -v "$name" 2>/dev/null || true)
	if [ -n "$path" ] && [ "$(minor_of "$path")" = "$want" ]; then
		found=$path
		break
	fi
done

if [ -n "$found" ]; then
	echo "ensure-python: using the base's CPython $want at $found"
else
	echo "ensure-python: the base has no CPython $want; installing it with uv"
	export UV_PYTHON_INSTALL_DIR=/opt/python UV_NO_CACHE=1
	"$uv" python install --no-bin "$want"
	found=$("$uv" python find --managed-python "$want")
fi

for name in "python$want" python3 python; do
	path=$(command -v "$name" 2>/dev/null || true)
	if [ -z "$path" ] || [ "$(minor_of "$path")" != "$want" ]; then
		ln -sf "$found" "/usr/local/bin/$name"
	fi
done

for name in "python$want" python3 python; do
	got=$(minor_of "$(command -v "$name")")
	[ "$got" = "$want" ] || die "$name on PATH is CPython '$got', not $want; check PATH order"
done
echo "ensure-python: python, python3 and python$want are CPython $want"
