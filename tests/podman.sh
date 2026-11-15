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

out=$(podman run --rm --hostname nested-host "$PODMAN_TEST_IMAGE" hostname 2>&1) || {
	echo "$out" >&2
	fail "podman run --hostname failed"
}
[ "$out" = nested-host ] || fail "a nested container's hostname is $out, want nested-host"
ok "a nested container can have its own hostname"

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

# The ansible podman flavour: a scenario for molecule-plugins' podman driver,
# which starts a container for each platform and connects to it with
# containers.podman. raw, as the test image has no Python; through Podman,
# raw runs its command without a shell unless given one.
if command -v molecule >/dev/null; then
	cd "$(mktemp -d)"
	mkdir -p molecule/default
	cat >molecule/default/molecule.yml <<YAML
---
driver:
  name: podman
platforms:
  - name: molecule-smoke-test
    image: "$PODMAN_TEST_IMAGE"
    pre_build_image: true
    command: ["sleep", "3600"]
scenario:
  test_sequence: [create, converge, verify, destroy]
YAML
	cat >molecule/default/converge.yml <<'YAML'
---
- name: Converge
  hosts: all
  gather_facts: false
  tasks:
    - name: Write a file
      ansible.builtin.raw: echo converged > /tmp/converged
      args:
        executable: /bin/sh
      changed_when: true
YAML
	cat >molecule/default/verify.yml <<'YAML'
---
- name: Verify
  hosts: all
  gather_facts: false
  tasks:
    - name: Read the file
      ansible.builtin.raw: cat /tmp/converged
      register: converged
      changed_when: false
    - name: Check it
      ansible.builtin.assert:
        that: "'converged' in converged.stdout"
YAML
	molecule test || fail "molecule test with the podman driver failed"
	ok "molecule test runs a scenario in a container it starts with Podman"
fi
