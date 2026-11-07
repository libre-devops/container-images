#!/bin/sh
# Creates the unprivileged user every image runs as: app, uid and gid 10001,
# home /home/app, and the working directory /work. Writes the account files
# directly rather than calling useradd, which minimal bases often lack.

set -eu

name=app
uid=10001
gid=10001
home=/home/app
work=/work
shell=/bin/bash

die() {
	printf 'create-user: %s\n' "$*" >&2
	exit 1
}

owner=$(awk -F: -v uid="$uid" '$3 == uid { print $1 }' /etc/passwd)
if [ -n "$owner" ]; then
	[ "$owner" = "$name" ] || die "uid $uid already belongs to '$owner'"
else
	if grep -q "^$name:" /etc/passwd; then
		die "user '$name' already exists with another uid"
	fi
	if ! awk -F: -v gid="$gid" '$3 == gid { found = 1 } END { exit !found }' /etc/group; then
		echo "$name:x:$gid:" >>/etc/group
		if [ -f /etc/gshadow ]; then
			echo "$name:!::" >>/etc/gshadow
		fi
	fi
	echo "$name:x:$uid:$gid:$name:$home:$shell" >>/etc/passwd
	if [ -f /etc/shadow ]; then
		echo "$name:!:1::::::" >>/etc/shadow
	fi
fi

mkdir -p "$home" "$work"
echo "create-user: $name ($uid:$gid), home $home, workdir $work"
