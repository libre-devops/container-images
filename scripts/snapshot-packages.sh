#!/usr/bin/env bash
# Records every container package in the Libre DevOps GHCR organisation and
# Docker Hub namespace, with each version's digest and tags, so that a
# snapshot taken before a release can be compared with one taken after.
# Nothing here may ever change or disappear an existing package or tag.
#
# Usage: scripts/snapshot-packages.sh <output directory>
#        diff -r <before> <after>
# Needs gh with the read:packages scope, curl and jq.

set -euo pipefail

out=${1:?usage: scripts/snapshot-packages.sh <output directory>}
org=libre-devops
hub=libredevops
mkdir -p "$out"

gh api --paginate "/orgs/$org/packages?package_type=container&per_page=100" --jq '.[].name' |
	sort >"$out/ghcr-packages.txt"
while read -r package; do
	encoded=$(jq -rn --arg p "$package" '$p | @uri')
	gh api --paginate "/orgs/$org/packages/container/$encoded/versions?per_page=100" |
		jq -r --arg p "$package" '.[] | [$p, .name, ((.metadata.container.tags // []) | sort | join(","))] | @tsv'
done <"$out/ghcr-packages.txt" | sort >"$out/ghcr-versions.tsv"

next="https://hub.docker.com/v2/namespaces/$hub/repositories?page_size=100"
: >"$out/dockerhub-repos.txt"
while [ -n "$next" ] && [ "$next" != null ]; do
	page=$(curl -fsS "$next")
	jq -r '.results[].name' <<<"$page" >>"$out/dockerhub-repos.txt"
	next=$(jq -r .next <<<"$page")
done
sort -o "$out/dockerhub-repos.txt" "$out/dockerhub-repos.txt"
while read -r repo; do
	next="https://hub.docker.com/v2/namespaces/$hub/repositories/$repo/tags?page_size=100"
	while [ -n "$next" ] && [ "$next" != null ]; do
		page=$(curl -fsS "$next")
		jq -r --arg r "$repo" '.results[] | [$r, .name, (.digest // "")] | @tsv' <<<"$page"
		next=$(jq -r .next <<<"$page")
	done
done <"$out/dockerhub-repos.txt" | sort >"$out/dockerhub-tags.tsv"

wc -l "$out"/*
