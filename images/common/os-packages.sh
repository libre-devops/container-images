#!/bin/sh
# Installs operating system packages by logical name on any base that has
# apt-get, dnf, microdnf or apk, so that no Containerfile names a package
# manager and a change of base image needs no edits to them.
#
# Usage: os-packages.sh [--upgrade] <logical name>...
#
#   --upgrade   Upgrade every installed package first, so that a scheduled
#               rebuild picks up the distribution's security fixes.
#   <name>?     A trailing ? marks a package as optional: if the base's
#               repositories do not carry it, the build carries on without it.
#
# Each logical name maps to candidate package names for the detected package
# manager, tried in order (libssl3t64 before libssl3, for example), so that a
# rename between releases does not break a build. Package caches are removed
# afterwards. Package databases are kept, because scanners read them.

set -eu

die() {
	printf 'os-packages: %s\n' "$*" >&2
	exit 1
}

pm=
for candidate in apt-get dnf microdnf apk; do
	if command -v "$candidate" >/dev/null 2>&1; then
		pm=$candidate
		break
	fi
done
[ -n "$pm" ] || die "no supported package manager found (apt-get, dnf, microdnf or apk)"

upgrade=false
if [ "${1:-}" = --upgrade ]; then
	upgrade=true
	shift
fi

export DEBIAN_FRONTEND=noninteractive
log=$(mktemp)
trap 'rm -f "$log"' EXIT

install_package() {
	case $pm in
	apt-get) apt-get install -y -qq --no-install-recommends "$@" ;;
	dnf) dnf install -y -q --setopt=install_weak_deps=False --nodocs "$@" ;;
	microdnf) microdnf install -y --setopt=install_weak_deps=0 --nodocs "$@" ;;
	apk) apk add --no-cache -q "$@" ;;
	esac
}

upgrade_all() {
	case $pm in
	apt-get) apt-get upgrade -y -qq ;;
	dnf) dnf upgrade -y -q ;;
	microdnf) microdnf upgrade -y ;;
	apk) apk upgrade --no-cache -q ;;
	esac
}

clean() {
	case $pm in
	apt-get) apt-get clean && rm -rf /var/lib/apt/lists/* ;;
	dnf) dnf clean all -q && rm -rf /var/cache/dnf ;;
	microdnf) microdnf clean all && rm -rf /var/cache/yum /var/cache/dnf ;;
	apk) rm -rf /var/cache/apk/* ;;
	esac
}

# candidates <logical name>: the package names to try, in order.
candidates() {
	case $pm:$1 in
	apt-get:icu) apt-cache pkgnames libicu | grep -E '^libicu[0-9]+$' | sort -V | tail -n 1 ;;
	apt-get:libstdc++) echo libstdc++6 ;;
	apt-get:openssl) echo libssl3t64 libssl3 ;;
	apt-get:shadow) echo passwd ;;
	apt-get:xz) echo xz-utils ;;
	apt-get:zlib) echo zlib1g ;;
	dnf:git | microdnf:git) echo git-core git ;;
	dnf:icu | microdnf:icu) echo libicu ;;
	dnf:openssl | microdnf:openssl) echo openssl-libs ;;
	dnf:shadow | microdnf:shadow) echo shadow-utils ;;
	dnf:zlib | microdnf:zlib) echo zlib-ng-compat zlib ;;
	apk:ca-certificates) echo ca-certificates ca-certificates-bundle ;;
	apk:icu) echo icu-libs icu ;;
	apk:openssl) echo libssl3 openssl ;;
	*) echo "$1" ;;
	esac
}

if [ "$pm" = apt-get ]; then
	apt-get update -qq
fi
if $upgrade; then
	upgrade_all
fi

for name in "$@"; do
	optional=false
	case $name in
	*\?)
		optional=true
		name=${name%?}
		;;
	esac
	# A tool the base already provides is good enough (and --upgrade keeps it
	# current): RHEL's curl-minimal conflicts with the full curl package, and
	# Wolfi's tar and gzip are busybox, with no separate package.
	case $name in
	bash | curl | git | gzip | tar | unzip | xz)
		if command -v "$name" >/dev/null 2>&1; then
			echo "os-packages: $name is already present"
			continue
		fi
		;;
	esac
	list=$(candidates "$name")
	[ -n "$list" ] || die "no package known for '$name' on $pm"
	installed=
	for package in $list; do
		if install_package "$package" >"$log" 2>&1; then
			installed=$package
			break
		fi
	done
	if [ -z "$installed" ] && $optional; then
		echo "os-packages: optional $name is not available from this base's repositories; carrying on without it"
		continue
	fi
	if [ -z "$installed" ]; then
		cat "$log" >&2
		die "could not install '$name' with $pm (tried: $list)"
	fi
	echo "os-packages: $name -> $installed ($pm)"
done

clean
