#!/bin/sh
# Configures Podman so that the app user (uid 10001) can run it rootless
# inside a container: Podman in Podman, or in Docker or Kubernetes.
#
# - Subordinate ids for app: every id from 1 to 65535 except its own, which
#   fits inside the 65536 ids a rootless outer container usually maps.
# - newuidmap and newgidmap with file capabilities rather than setuid root,
#   which is what lets them write the nested id maps (as quay.io/podman/stable
#   does).
# - Storage through fuse-overlayfs (storage.conf): the kernel's overlay cannot
#   mount over the outer container's own overlay, and newer Buildah overlays
#   the build context too.
# - Containers that share the outer container's namespaces and need no
#   cgroups (containers.conf), and builds that isolate RUN steps with chroot
#   (BUILDAH_ISOLATION in the Containerfile), since a nested container cannot
#   create most namespaces of its own.
# - A docker command that runs Podman, without its notice on every call.
#
# The outer container needs /dev/fuse (--device /dev/fuse), for
# fuse-overlayfs, and on SELinux hosts --security-opt label=disable.

set -eu

die() {
	printf 'podman setup: %s\n' "$*" >&2
	exit 1
}

user=app
for file in /etc/subuid /etc/subgid; do
	touch "$file"
	sed -i "/^$user:/d" "$file"
	printf '%s:1:10000\n%s:10002:55534\n' "$user" "$user" >>"$file"
done

for tool in newuidmap newgidmap; do
	path=$(command -v "$tool") || die "$tool is missing (the uidmap package)"
	case $tool in
	newuidmap) cap=cap_setuid ;;
	newgidmap) cap=cap_setgid ;;
	esac
	chmod 0755 "$path"
	setcap "$cap=ep" "$path" || die "cannot set $cap on $path"
done

mkdir -p /etc/containers
cat >/etc/containers/containers.conf <<'CONF'
# Podman in a container: nested containers share the outer container's
# namespaces and need no cgroups of their own (see images/podman/setup.sh).
[containers]
netns = "host"
userns = "host"
ipcns = "host"
utsns = "host"
cgroupns = "host"
cgroups = "disabled"
log_driver = "k8s-file"

[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"
runtime = "crun"
CONF

fuse=$(command -v fuse-overlayfs) || die "fuse-overlayfs is missing"
cat >/etc/containers/storage.conf <<CONF
# Podman in a container: overlays through fuse-overlayfs, since the kernel's
# overlay cannot mount over the outer container's (see images/podman/setup.sh).
[storage]
driver = "overlay"

[storage.options.overlay]
mount_program = "$fuse"
mountopt = "nodev,fsync=0"
CONF

if command -v docker >/dev/null 2>&1; then
	touch /etc/containers/nodocker
fi
echo "podman setup: $(podman --version), rootless for $user"
