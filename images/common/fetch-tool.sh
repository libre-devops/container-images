#!/bin/sh
# Downloads one pinned release asset, checks it against its pinned SHA-256 and
# installs it under a staging root laid out like / (executables go to
# <root>/usr/local/bin). POSIX sh, so it runs on any base before bash exists,
# and on CI runners for the CI tools.
#
# Usage: fetch-tool.sh <root> <tool> <spec>
#
# <spec> comes from versions.lock.json, through scripts/images.py: one or more
# space-separated "<platform>|<url>|<sha256>" items, where <platform> is
# amd64, arm64, amd64-musl, arm64-musl or any. On a musl base (Alpine), a tool
# that ships separate musl builds must have one for this architecture; a tool
# with a single build (a static binary) uses it everywhere. A download whose
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

libc=gnu
for loader in /lib/ld-musl-*.so.1; do
	[ -e "$loader" ] && libc=musl
done

# pick <platform>: the url and sha of the item for that platform, if any.
pick() {
	for item in $spec; do
		case $item in
		"$1|"*)
			rest=${item#*|}
			url=${rest%|*}
			sha=${rest##*|}
			return 0
			;;
		esac
	done
	return 1
}

url=
sha=
case " $spec" in
*" "*-musl\|*) has_musl_builds=true ;;
*) has_musl_builds=false ;;
esac
if [ "$libc" = musl ] && $has_musl_builds; then
	pick "$arch-musl" || die "$tool has no musl build for $arch, so it cannot run on this base"
else
	pick "$arch" || pick any || die "no $arch download is pinned for $tool"
fi
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
		found=$(find "$work/x" -type f -name "$name" | sed -n 1p)
		[ -n "$found" ] || die "$name is not in ${url##*/}"
		install -m 0755 "$found" "$bin/$name"
	done
}

case $tool in
shfmt | jq | hadolint | cosign) install -m 0755 "$file" "$bin/$tool" ;;
shellcheck | trivy | zizmor | actionlint | tfstacks) unpack && put "$tool" ;;
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
azure-azcollection) mkdir -p "$root/collections" && cp "$file" "$root/collections/" ;;
# The agents are unpacked by images/agents/install.sh, straight into the
# directory they run from, so their files are copied into the image only once.
azure-pipelines-agent | github-runner | openssh) mkdir -p "$root/archive" && cp "$file" "$root/archive/" ;;
*) die "unknown tool: $tool" ;;
esac
