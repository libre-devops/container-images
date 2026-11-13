#!/bin/sh
# Builds the OpenSSH client tools from the pinned upstream release, whose
# signature `just lock` verified before pinning its SHA-256.
#
# Why from source: the ansible images need ssh, and Debian's openssh-client
# lags upstream security fixes. CVE-2026-60002 (critical; fixed in OpenSSH
# 10.4) was still unfixed in Debian 13 on 2026-11-13. This follows the latest
# release, which Renovate bumps. Once the distribution's package carries every
# fix the scan gate needs, go back to it (os_packages: ssh) and remove this
# stage: see "Built from source" in the README.
#
# Usage: build-openssh.sh <tarball directory> <output root>

set -eu

die() {
	printf 'build-openssh: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 2 ] || die "usage: build-openssh.sh <tarball directory> <output root>"
set -- "$1"/openssh-*.tar.gz "$2"
[ "$#" -eq 2 ] && [ -f "$1" ] || die "expected exactly one OpenSSH tarball"
out=$2

work=$(mktemp -d)
tar -xzf "$1" -C "$work"
cd "$work"/openssh-*

# The client only; configure turns on the compiler's hardening flags itself.
./configure --prefix=/usr/local --sysconfdir=/etc/ssh >configure.log 2>&1 || {
	tail -n 40 configure.log >&2
	die "configure failed"
}
tools="ssh scp sftp ssh-add ssh-agent ssh-keygen ssh-keyscan"
# shellcheck disable=SC2086 # tools is a list
make -j"$(nproc)" $tools >make.log 2>&1 || {
	tail -n 40 make.log >&2
	die "make failed"
}
mkdir -p "$out/usr/local/bin"
# shellcheck disable=SC2086
install -m 0755 $tools "$out/usr/local/bin/"
"$out/usr/local/bin/ssh" -V
