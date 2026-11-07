#!/bin/sh
# Downloads one pinned release asset, checks it against its pinned SHA-256 and
# installs it under a staging root laid out like / (executables go to
# <root>/usr/local/bin). POSIX sh, so it runs on any base before bash exists,
# and on CI runners for the CI tools.
#
# Usage: fetch-tool.sh <root> <tool> <spec>
#
# <spec> comes from versions.lock.json, through scripts/images.py: one or more
# space-separated "<arch>|<url>|<sha256>" items, where <arch> is amd64, arm64
# or any. The item for this machine's architecture is used. A download whose
# SHA-256 does not match the pin fails the build.

set -eu

die() {
	printf 'fetch-tool: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 3 ] || die "usage: fetch-tool.sh <root> <tool> <spec>"
root=$1
tool=$2
spec=$3

case $(uname -m) in
x86_64 | amd64) arch=amd64 ;;
aarch64 | arm64) arch=arm64 ;;
*) die "unsupported architecture: $(uname -m)" ;;
esac

url=
sha=
for item in $spec; do
	case $item in
	"$arch|"* | "any|"*)
		rest=${item#*|}
		url=${rest%|*}
		sha=${rest##*|}
		break
		;;
	esac
done
[ -n "$url" ] || die "no $arch download is pinned for $tool"
case $sha in
"" | *[!0-9a-f]*) die "the pinned SHA-256 for $tool is not hex: '$sha'" ;;
esac
[ "${#sha}" -eq 64 ] || die "the pinned SHA-256 for $tool is not 64 characters"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
file=$work/${url##*/}

curl -fsSL --retry 5 --retry-connrefused -o "$file" "$url"
actual=$(sha256sum "$file" | cut -d ' ' -f 1)
[ "$actual" = "$sha" ] || die "SHA-256 mismatch for $url: pinned $sha, downloaded $actual"
echo "fetch-tool: ${url##*/} matches its pinned SHA-256"

bin=$root/usr/local/bin
mkdir -p "$bin"

unpack() {
	mkdir -p "$work/x"
	case $file in
	*.tar.gz) tar -xzf "$file" -C "$work/x" ;;
	*.tar.xz) tar -xJf "$file" -C "$work/x" ;;
	*.zip) unzip -q "$file" -d "$work/x" ;;
	*) die "do not know how to unpack ${file##*/}" ;;
	esac
}

# put <name>...: installs each named executable from the unpacked archive.
put() {
	for name in "$@"; do
		found=$(find "$work/x" -type f -name "$name" | head -n 1)
		[ -n "$found" ] || die "$name is not in ${url##*/}"
		install -m 0755 "$found" "$bin/$name"
	done
}

case $tool in
shfmt | jq | hadolint | cosign) install -m 0755 "$file" "$bin/$tool" ;;
shellcheck | trivy | zizmor | actionlint) unpack && put "$tool" ;;
uv) unpack && put uv uvx ;;
go)
	mkdir -p "$root/usr/local"
	rm -rf "$root/usr/local/go"
	tar -xzf "$file" -C "$root/usr/local"
	;;
powershell)
	dest=$root/opt/microsoft/powershell/7
	mkdir -p "$dest"
	tar -xzf "$file" -C "$dest"
	chmod 0755 "$dest/pwsh"
	ln -sf /opt/microsoft/powershell/7/pwsh "$bin/pwsh"
	;;
ldo-cli) mkdir -p "$root/wheels" && cp "$file" "$root/wheels/" ;;
*) die "unknown tool: $tool" ;;
esac
