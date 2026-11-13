#!/bin/sh
# Adds CA certificates to the operating system's trust store, on any base these
# images support. Every tool in the images trusts that store: curl, git, Go
# tools such as Terraform, PowerShell and .NET, Python (pip-system-certs and
# REQUESTS_CA_BUNDLE), pip, uv and Node (NODE_EXTRA_CA_CERTS). For a network
# whose TLS inspection presents an organisation's own root CA.
#
# Usage, as root (typically in a Dockerfile FROM one of these images):
#   add-ca-certificates <PEM file>...
# A file may hold several certificates.

set -eu

die() {
	printf 'add-ca-certificates: %s\n' "$*" >&2
	exit 1
}

[ "$#" -gt 0 ] || die "usage: add-ca-certificates <PEM file>..."
[ "$(id -u)" -eq 0 ] || die "run as root (USER root in a Dockerfile, then USER 10001:10001 again)"

if command -v update-ca-trust >/dev/null 2>&1; then
	anchors=/etc/pki/ca-trust/source/anchors
	update() { update-ca-trust extract; }
elif command -v update-ca-certificates >/dev/null 2>&1; then
	anchors=/usr/local/share/ca-certificates
	update() { update-ca-certificates >/dev/null 2>&1 || update-ca-certificates; }
else
	die "this base has neither update-ca-trust nor update-ca-certificates"
fi
mkdir -p "$anchors"

for file in "$@"; do
	[ -r "$file" ] || die "cannot read $file"
	grep -q -e '-----BEGIN CERTIFICATE-----' "$file" || die "$file holds no PEM certificate"
	name=$(basename "$file")
	name=${name%.*}
	# One certificate per file: update-ca-certificates reads only the first.
	count=$(awk -v out="$anchors/$name" '
		/-----BEGIN CERTIFICATE-----/ { n++; f = sprintf("%s-%d.crt", out, n); inside = 1 }
		inside { print > f }
		/-----END CERTIFICATE-----/ { inside = 0; close(f) }
		END { print n }
	' "$file")
	echo "add-ca-certificates: $file ($count certificate(s))"
done
update
echo "add-ca-certificates: the trust store at /etc/ssl/certs/ca-certificates.crt is updated"
