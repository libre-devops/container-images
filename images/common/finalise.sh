#!/bin/sh
# The last root step of every image. Hands /home/app and /work to the app user
# and makes them group-writable for gid 0, so an arbitrary uid that runs with
# gid 0 (OpenShift, or `docker run --user 1001:0` in a GitHub Actions
# container job) can write to them too. Then clears build leftovers.

set -eu

for dir in /home/app /work; do
	chown -R 10001:0 "$dir"
	chmod -R g=u "$dir"
done

rm -rf /root/.cache /root/.local /tmp/* /var/tmp/*
