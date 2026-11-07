#!/bin/sh
# Builds one Go tool from its pinned module source, with the pinned Go
# toolchain at /usr/local/go, and installs its binaries under <root>.
#
# The source comes from the Go module proxy and is verified against the Go
# checksum database, as are its dependencies. Before building, every
# dependency with a known vulnerability is raised to the fixed version that
# `just lock` recorded in versions.lock.json (from OSV), so the binary carries
# neither the toolchain's nor its dependencies' known vulnerabilities.
#
# Usage: go-build.sh <root> <spec>
#   spec  module;version;package:binary[,package:binary...];ldflags;overrides
#         where overrides is a space-separated list of module@version.

set -eu

die() {
	printf 'go-build: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 2 ] || die "usage: go-build.sh <root> <spec>"
root=$1
IFS=';' read -r module version packages ldflags overrides <<EOF
$2
EOF
[ -n "$module" ] && [ -n "$version" ] && [ -n "$packages" ] || die "incomplete spec: $2"

export PATH="/usr/local/go/bin:$PATH"
export GOTOOLCHAIN=local CGO_ENABLED=0 GOFLAGS=-mod=mod
export GOPROXY="${GOPROXY:-https://proxy.golang.org}" GOSUMDB="${GOSUMDB:-sum.golang.org}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

source_dir=$(go mod download -json "$module@$version" | sed -n 's/^[[:space:]]*"Dir": "\(.*\)",$/\1/p')
[ -d "$source_dir" ] || die "could not download $module@$version"
cp -R "$source_dir" "$work/src"
chmod -R u+w "$work/src"
cd "$work/src"

# semver_lt <a> <b>: true if Go module version a sorts before b (semver
# rules: a pre-release, including a pseudo-version, sorts before its release).
semver_lt() {
	awk -v a="$1" -v b="$2" '
	function cmp_ids(x, y,   xs, ys, nx, ny, i, xn, yn) {
		nx = split(x, xs, "."); ny = split(y, ys, ".")
		for (i = 1; i <= nx && i <= ny; i++) {
			xn = (xs[i] ~ /^[0-9]+$/); yn = (ys[i] ~ /^[0-9]+$/)
			if (xn && yn) { if (xs[i] + 0 != ys[i] + 0) return (xs[i] + 0 < ys[i] + 0) ? -1 : 1 }
			else if (xn != yn) return xn ? -1 : 1
			else if (xs[i] != ys[i]) return (xs[i] < ys[i]) ? -1 : 1
		}
		return (nx == ny) ? 0 : (nx < ny ? -1 : 1)
	}
	function cmp(x, y,   xc, yc, xp, yp, c) {
		sub(/^v/, "", x); sub(/^v/, "", y); sub(/\+.*$/, "", x); sub(/\+.*$/, "", y)
		xc = x; xp = ""; if (index(x, "-")) { xc = substr(x, 1, index(x, "-") - 1); xp = substr(x, index(x, "-") + 1) }
		yc = y; yp = ""; if (index(y, "-")) { yc = substr(y, 1, index(y, "-") - 1); yp = substr(y, index(y, "-") + 1) }
		c = cmp_ids(xc, yc); if (c != 0) return c
		if (xp == "" && yp == "") return 0
		if (xp == "") return 1
		if (yp == "") return -1
		return cmp_ids(xp, yp)
	}
	BEGIN { exit !(cmp(a, b) < 0) }'
}

selected() {
	go list -m -f '{{.Version}}' "$1" 2>/dev/null || true
}

# Only ever raise: `go get m@v` sets m to exactly v and lowers anything that
# needs more, so a fix already exceeded (because another fix pulled the
# module higher) is skipped rather than re-applied.
for override in $overrides; do
	mod=${override%@*}
	want=${override#*@}
	have=$(selected "$mod")
	if [ -n "$have" ] && ! semver_lt "$have" "$want"; then
		echo "go-build: $module: $mod is already at $have (needs $want)"
		continue
	fi
	echo "go-build: $module: raising $mod from ${have:-none} to $want (known vulnerability fixed there)"
	go get "$mod@$want"
done
for override in $overrides; do
	mod=${override%@*}
	want=${override#*@}
	have=$(selected "$mod")
	if semver_lt "$have" "$want"; then
		die "$mod ended at $have, below the fixed $want"
	fi
done

pkgs=
for pair in $(echo "$packages" | tr ',' ' '); do
	pkgs="$pkgs ${pair%%:*}"
done
# shellcheck disable=SC2086 # pkgs is a list of package paths
go list -deps $pkgs >/dev/null

# A clean, tagged checkout makes the toolchain stamp the release version
# into the binary, as an upstream release build would.
git init -q
git add -A
git -c user.name=build -c user.email=build@localhost commit -q -m "$module $version"
git tag "$version"

mkdir -p "$root/usr/local/bin"
for pair in $(echo "$packages" | tr ',' ' '); do
	pkg=${pair%%:*}
	bin=${pair#*:}
	GOFLAGS=-mod=readonly go build -trimpath -buildvcs=true -ldflags "-s -w $ldflags" \
		-o "$root/usr/local/bin/$bin" "$pkg"
	echo "go-build: built $bin from $module $version with $(go env GOVERSION)"
done
