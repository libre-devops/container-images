#!/bin/sh
# Runs a command, retrying it with backoff when it fails: for build steps that
# download, so that a registry's or a CDN's bad moment does not fail a build.
#
# Usage: retry.sh <command> [argument]...

set -eu

[ "$#" -gt 0 ] || {
	echo "usage: retry.sh <command> [argument]..." >&2
	exit 1
}
attempts=4
n=1
until "$@"; do
	if [ "$n" -ge "$attempts" ]; then
		echo "retry: '$*' failed $attempts times" >&2
		exit 1
	fi
	echo "retry: '$*' failed (attempt $n), retrying in $((n * 15))s" >&2
	sleep $((n * 15))
	n=$((n + 1))
done
