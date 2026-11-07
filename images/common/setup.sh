#!/bin/sh
# Shared root setup for the base stage of every image: upgraded OS packages,
# the shared set plus any extras the image asks for in OS_PACKAGES (logical
# names, space-separated), the app user, and git configuration.
#
# shadow (useradd and groupadd) is included because the Azure Pipelines agent
# adds its own user inside container jobs. It is optional because some musl
# bases (Docker Hardened Images' Alpine) do not carry it, and Azure Pipelines
# container jobs need glibc anyway.

set -eu

lib=$(dirname "$0")

# shellcheck disable=SC2086 # OS_PACKAGES is a space-separated list
sh "$lib/os-packages.sh" --upgrade bash ca-certificates curl git 'shadow?' ${OS_PACKAGES:-}
sh "$lib/create-user.sh"

# CI systems often mount a workspace owned by another uid, which git otherwise
# refuses to work in ("detected dubious ownership").
git config --system --add safe.directory '*'
