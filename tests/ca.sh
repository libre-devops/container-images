# The CA trust test, run as root: adds a test CA with add-ca-certificates, then
# checks that every TLS client in the image trusts a server whose certificate
# it signed (the server runs in another container: see tests/run.sh). This is
# what an organisation with TLS inspection does with its own root CA.
# Reads TEST_CA (the CA certificate, PEM) and TLS_URL from the environment.
# shellcheck shell=bash disable=SC2016 # PowerShell and JavaScript, expanded by pwsh and node, not bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

[ "$(id -u)" = 0 ] || fail "the CA trust test must run as root"
printf '%s\n' "$TEST_CA" >/tmp/test-ca.pem

if curl -fsS -o /dev/null "$TLS_URL" 2>/dev/null; then
	fail "curl trusted the test server before its CA was added"
fi
add-ca-certificates /tmp/test-ca.pem
grep -qF "$(sed -n 2p /tmp/test-ca.pem)" /etc/ssl/certs/ca-certificates.crt ||
	fail "the test CA is not in /etc/ssl/certs/ca-certificates.crt"
ok "add-ca-certificates added the test CA to the system bundle"

[ "$(curl -fsS "$TLS_URL")" = ok ] || fail "curl does not trust the test CA"
ok "curl"

out=$(git ls-remote "$TLS_URL" 2>&1 || true)
if grep -qiE 'certificate|SSL' <<<"$out"; then
	echo "$out" >&2
	fail "git does not trust the test CA"
fi
ok "git"

# Python, with and without REQUESTS_CA_BUNDLE: in the images' own virtual
# environments pip-system-certs makes requests use the system store regardless.
for python in python3 /opt/az/bin/python /opt/ldo-cli/bin/python /opt/ansible/bin/python; do
	command -v "$python" >/dev/null || continue
	"$python" -c 'import os, urllib.request; assert urllib.request.urlopen(os.environ["TLS_URL"]).read() == b"ok\n"' ||
		fail "$python (urllib) does not trust the test CA"
	if "$python" -c 'import requests' 2>/dev/null; then
		"$python" -c 'import os, requests; requests.get(os.environ["TLS_URL"]).raise_for_status()' ||
			fail "$python (requests) does not trust the test CA"
		if "$python" -c 'import pip_system_certs' 2>/dev/null; then
			env -u REQUESTS_CA_BUNDLE "$python" -c 'import os, requests; requests.get(os.environ["TLS_URL"]).raise_for_status()' ||
				fail "$python (requests, through pip-system-certs) does not trust the test CA"
		fi
	fi
	ok "$python"
done

if command -v uv >/dev/null; then
	out=$(cd "$(mktemp -d)" && echo nothing-here | uv pip compile --no-cache --index-url "${TLS_URL}simple" - 2>&1 || true)
	if grep -qiE 'certificate|UnknownIssuer|invalid peer' <<<"$out"; then
		echo "$out" >&2
		fail "uv does not trust the test CA"
	fi
	ok "uv"
fi

if command -v pwsh >/dev/null; then
	pwsh -NoLogo -NoProfile -NonInteractive -Command \
		'$ErrorActionPreference = "Stop"; if ((Invoke-WebRequest -Uri $env:TLS_URL).Content.Trim() -ne "ok") { throw "unexpected body" }' ||
		fail "PowerShell does not trust the test CA"
	ok "PowerShell (.NET)"
fi

for node in /opt/actions-runner/externals/node*/bin/node /opt/azure-pipelines-agent/externals/node*/bin/node; do
	[ -x "$node" ] || continue
	"$node" -e 'require("https").get(process.env.TLS_URL, r => process.exit(r.statusCode === 200 ? 0 : 1)).on("error", e => { console.error(e.message); process.exit(1) })' ||
		fail "$node does not trust the test CA"
	ok "$node"
done
