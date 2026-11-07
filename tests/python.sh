# Smoke tests for the python image.
# shellcheck shell=bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

python --version
uv --version

for name in python python3 "python$EXPECT_PYTHON"; do
	got=$("$name" -c 'import sys; print("%d.%d" % sys.version_info[:2])')
	[ "$got" = "$EXPECT_PYTHON" ] || fail "$name is CPython $got, want $EXPECT_PYTHON"
done
ok "python, python3 and python$EXPECT_PYTHON are CPython $EXPECT_PYTHON"

[ "$(uv --version | cut -d ' ' -f 2)" = "$EXPECT_UV" ] || fail "uv is not $EXPECT_UV"
ok "uv $EXPECT_UV"

python -c 'import ctypes, sqlite3, ssl, venv, zlib; print(ssl.OPENSSL_VERSION)'
ok "standard library extension modules import"

cd "$(mktemp -d)"
uv venv --quiet --python "$EXPECT_PYTHON" .venv
uv pip install --quiet --python .venv/bin/python 'packaging==25.0'
.venv/bin/python -c 'import packaging; print("packaging", packaging.__version__)'
ok "uv creates a virtual environment and installs into it as the app user"
