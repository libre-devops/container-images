# Libre DevOps container images. Run `just` to list the recipes.
#
# Every recipe calls the same scripts the GitHub Actions workflows run, so a
# local run shows what CI will do. Docker or Podman is picked automatically;
# set ENGINE to choose.

set shell := ["bash", "-euo", "pipefail", "-c"]

images := "uv run --quiet scripts/images.py"

# List the recipes.
default:
    @just --list

# Build an image for this machine: just build python 3.13 [base key or reference].
build image version="" base="":
    scripts/build.sh '{{ image }}' '{{ version }}' '{{ base }}'

# Build an image, then run its smoke tests.
test image version="" base="":
    tests/run.sh '{{ image }}' "$(scripts/build.sh '{{ image }}' '{{ version }}' '{{ base }}')" '{{ version }}'

# Build an image, then scan it with the release gate (needs Trivy: just tools).
scan image version="" base="":
    scripts/scan.sh "$(scripts/build.sh '{{ image }}' '{{ version }}' '{{ base }}')" '{{ image }}' '{{ version }}' '{{ base }}'

# Write README.md from HEADER.md and versions.yml.
docs:
    {{ images }} docs

# Fail if README.md is out of date.
docs-check:
    {{ images }} docs --check

# Pin the SHA-256 of every new download in versions.lock.json.
lock:
    {{ images }} lock

# Re-resolve every base image tag in versions.yml to its current digest.
pin:
    {{ images }} pin

# Check versions.yml, the lock and the base pins.
validate:
    {{ images }} validate

# Lint Containerfiles, shell scripts and text (needs: just tools).
lint:
    PATH="$PWD/.tools/usr/local/bin:$PATH" scripts/lint.sh

# Install the pinned CI tools into .tools.
tools:
    scripts/ci-tools.sh hadolint shellcheck shfmt trivy cosign

# List every package and tag in GHCR and Docker Hub, for before and after comparisons.
snapshot dir:
    scripts/snapshot-packages.sh '{{ dir }}'
