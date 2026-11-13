#!/usr/bin/env bash
# Runs the smoke tests for one image: the shared checks, each of the image's
# suites (the toolbox runs every included image's), a write check as an
# arbitrary uid in group 0, and the CA trust test (tests/ca.sh) against a TLS
# server in a second container. Each test script is piped to bash inside the
# container, so nothing is mounted and the tests behave the same under
# Docker, rootless Podman and SELinux. Needs openssl on the host.
#
# Usage: tests/run.sh <image> <reference> [version]
#   version  Defaults to the image's latest version in versions.yml; it sets
#            the versions the tests expect.

set -euo pipefail

image=${1:?usage: tests/run.sh <image> <reference> [version]}
ref=${2:?usage: tests/run.sh <image> <reference> [version]}
version=${3:-}
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
engine=$("$root/scripts/engine.sh")
images=(uv run --quiet "$root/scripts/images.py")

env_args=()
while IFS= read -r kv; do
	env_args+=(-e "$kv")
done < <("${images[@]}" test-env "$image" "$version")
mapfile -t suites < <("${images[@]}" test-suites "$image" "$version")

run() {
	"$engine" run --rm -i "${env_args[@]}" "$@"
}

echo "== $ref: shared checks"
run "$ref" bash -s <"$here/common.sh"
for suite in "${suites[@]}"; do
	echo "== $ref: $suite checks"
	run "$ref" bash -s <"$here/$suite.sh"
done
echo "== $ref: arbitrary uid in group 0"
run --user 4242:0 "$ref" bash -s <"$here/arbitrary-uid.sh"

echo "== $ref: a CA added with add-ca-certificates is trusted everywhere"
work=$(mktemp -d)
name=ca-test-$$
cleanup() {
	"$engine" rm -f "$name-server" >/dev/null 2>&1 || true
	"$engine" network rm "$name" >/dev/null 2>&1 || true
	rm -rf "$work"
}
trap cleanup EXIT
# A CA and a server certificate that pass Python 3.13's strict X.509 checks.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=Smoke Test CA" \
	-keyout "$work/ca.key" -out "$work/ca.pem" \
	-addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
	-addext "subjectKeyIdentifier=hash" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=$name-server" \
	-keyout "$work/server.key" -out "$work/server.csr" 2>/dev/null
printf '%s\n' "basicConstraints=critical,CA:FALSE" "keyUsage=critical,digitalSignature,keyEncipherment" \
	"extendedKeyUsage=serverAuth" "subjectAltName=DNS:$name-server" \
	"subjectKeyIdentifier=hash" "authorityKeyIdentifier=keyid" >"$work/server.ext"
openssl x509 -req -in "$work/server.csr" -CA "$work/ca.pem" -CAkey "$work/ca.key" -CAcreateserial \
	-days 1 -extfile "$work/server.ext" -out "$work/server.pem" 2>/dev/null
"$engine" network create "$name" >/dev/null
server_image=$("${images[@]}" test-server-image)
# shellcheck disable=SC2016 # Python code, run by the server container
"$engine" run -d --name "$name-server" --network "$name" --user 0 --entrypoint python3 \
	-e SERVER_PEM="$(cat "$work/server.pem" "$work/server.key")" "$server_image" -c '
import http.server, os, ssl
with open("/tmp/server.pem", "w") as f:
    f.write(os.environ["SERVER_PEM"])
class Ok(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok\n")
    def log_message(self, *args):
        pass
server = http.server.ThreadingHTTPServer(("0.0.0.0", 8443), Ok)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain("/tmp/server.pem")
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
' >/dev/null
for _ in $(seq 30); do
	"$engine" exec "$name-server" python3 -c 'import socket; socket.create_connection(("127.0.0.1", 8443), 1)' 2>/dev/null && break
	sleep 1
done
run --user 0 --network "$name" -e TEST_CA="$(cat "$work/ca.pem")" -e TLS_URL="https://$name-server:8443/" \
	"$ref" bash -s <"$here/ca.sh"
echo "== $ref: all smoke tests passed"
