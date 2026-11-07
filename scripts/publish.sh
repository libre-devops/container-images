#!/usr/bin/env bash
# Publishes one image version, in the Release workflow, from the
# per-platform digests its build jobs pushed:
#
#   1. Joins them into one multi-platform manifest and tags it in every
#      registry in versions.yml (GHCR and Docker Hub) in one operation.
#   2. Checks every registry now serves the same digest for the date tag.
#   3. Signs that digest in every registry with cosign keyless signing.
#   4. Writes release/<image>-<version>.json for the README tables.
#
# Tags: the date tag is never overwritten. If it already exists (a second
# release on the same day), .2, .3 and so on are appended. The version, alias
# and latest tags move to the new digest.
#
# Usage: scripts/publish.sh <image> <version> <YYYYMMDD> <digest directory>

set -euo pipefail

cd "$(dirname "$0")/.."
image=${1:?} version=${2:?} date=${3:?} digest_dir=${4:?}
images=(uv run --quiet scripts/images.py)

mapfile -t repos < <("${images[@]}" repos "$image")
tags=$("${images[@]}" tags "$image" "$version" "$date")
date_tag=$(jq -r .date_tag <<<"$tags")
mapfile -t moving < <(jq -r '.moving[]' <<<"$tags")
platforms=$(jq -r .platforms <<<"$tags")

mapfile -t digests < <(cat "$digest_dir"/* 2>/dev/null || true)
if [ "${#digests[@]}" -ne "$platforms" ]; then
	echo "::error::$image $version has ${#digests[@]} platform digest(s), expected $platforms; a build job failed"
	exit 1
fi

# exists <ref>: 0 if the tag exists, 1 if it does not, and stops on anything
# else, so that a registry error can never lead to overwriting a date tag.
exists() {
	local out
	if out=$(docker buildx imagetools inspect --raw "$1" 2>&1 >/dev/null); then
		return 0
	fi
	if grep -qiE 'not found|manifest unknown|name unknown' <<<"$out"; then
		return 1
	fi
	echo "::error::cannot tell whether $1 exists: $out"
	exit 1
}

tag=$date_tag
n=1
while :; do
	taken=false
	for repo in "${repos[@]}"; do
		if exists "$repo:$tag"; then
			taken=true
		fi
	done
	$taken || break
	n=$((n + 1))
	tag=$date_tag.$n
done

args=()
for repo in "${repos[@]}"; do
	for t in "$tag" "${moving[@]}"; do
		args+=(--tag "$repo:$t")
	done
done
sources=()
for digest in "${digests[@]}"; do
	sources+=("${repos[0]}@$digest")
done
docker buildx imagetools create "${args[@]}" "${sources[@]}"

digest_of() {
	docker buildx imagetools inspect --format '{{json .Manifest}}' "$1" | jq -r .digest
}
digest=$(digest_of "${repos[0]}:$tag")
for repo in "${repos[@]:1}"; do
	other=$(digest_of "$repo:$tag")
	if [ "$other" != "$digest" ]; then
		echo "::error::$repo:$tag is $other but ${repos[0]}:$tag is $digest"
		exit 1
	fi
done

for repo in "${repos[@]}"; do
	cosign sign --yes "$repo@$digest"
done

mkdir -p release
jq -n --arg image "$image" --arg version "$version" --arg date_tag "$tag" \
	--arg digest "$digest" --arg released "$(date -u +%F)" \
	'{image: $image, version: $version, date_tag: $date_tag, digest: $digest, released: $released}' \
	>"release/$image-$version.json"

{
	echo "### $image $version"
	echo
	echo "Digest \`$digest\`, in every registry:"
	echo
	for repo in "${repos[@]}"; do
		# shellcheck disable=SC2016 # literal backticks for markdown
		echo "- \`$repo:$tag\` (also $(printf '`%s` ' "${moving[@]}"))"
	done
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "publish: $image $version is $digest, tagged $tag ${moving[*]}"
