# Smoke tests for Podman in a container: run as the app user, rootless, it
# pulls, runs and builds images. tests/run.sh starts this suite with the outer
# flags Podman in a container needs.
# shellcheck shell=bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

version=$(podman --version)
# The distribution's Podman: at least the major version the image is named
# for (Wolfi, a portability base, is already on a newer one).
[ "$(grep -oE '[0-9]+' <<<"$version" | head -n 1)" -ge "$EXPECT_PODMAN" ] || fail "$version is older than Podman $EXPECT_PODMAN"
ok "$version"

[ "$(id -u)" = 10001 ] || fail "not running as app"
grep -q '^app:1:10000$' /etc/subuid || fail "app has no subordinate uids"

out=$(podman run --rm "$PODMAN_TEST_IMAGE" echo nested-run-ok 2>&1) || {
	echo "$out" >&2
	fail "podman run failed"
}
grep -q nested-run-ok <<<"$out" || fail "podman run printed: $out"
ok "rootless podman run inside the container"

dir=$(mktemp -d)
printf 'FROM %s\nRUN echo built-ok > /built\n' "$PODMAN_TEST_IMAGE" >"$dir/Containerfile"
podman build -q -t localhost/smoke-test "$dir" >/dev/null || fail "podman build failed"
[ "$(podman run --rm localhost/smoke-test cat /built)" = built-ok ] || fail "the built image does not run"
ok "rootless podman build inside the container"

if command -v docker >/dev/null; then
	out=$(docker images 2>&1) || fail "the docker command fails: $out"
	grep -q localhost/smoke-test <<<"$out" || fail "docker does not see Podman's images"
	ok "the docker command runs Podman"
fi
