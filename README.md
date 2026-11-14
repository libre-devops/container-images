<!-- Generated from HEADER.md and versions.yml by `just docs`. Edit those, not this file. -->
<!--
  Keep the title and badges OUTSIDE the centred <div>: some markdown renderers do not
  parse markdown inside an HTML block, so a # heading or [![badge]] in the div renders as
  literal text. Only the logo (HTML) goes in the div.
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="300">
    </picture>
  </a>
</div>

# Libre DevOps Container Images

Thin, hardened, version-pinned images for CI jobs and tooling: built from pinned inputs on
Docker Hardened Images, scanned before and after publishing, signed, and published to GHCR and
Docker Hub from the same digest.

[![Build](https://github.com/libre-devops/container-images/actions/workflows/build.yml/badge.svg)](https://github.com/libre-devops/container-images/actions/workflows/build.yml)
[![Release](https://github.com/libre-devops/container-images/actions/workflows/release.yml/badge.svg)](https://github.com/libre-devops/container-images/actions/workflows/release.yml)
[![Scan](https://github.com/libre-devops/container-images/actions/workflows/scan.yml/badge.svg)](https://github.com/libre-devops/container-images/actions/workflows/scan.yml)
[![Licence](https://img.shields.io/github/license/libre-devops/container-images?label=licence)](./LICENSE)
[![GHCR](https://img.shields.io/badge/GHCR-libre--devops-2088FF?logo=github&logoColor=white)](https://github.com/orgs/libre-devops/packages?repo_name=container-images)
[![Docker Hub](https://img.shields.io/badge/Docker%20Hub-libredevops-2496ED?logo=docker&logoColor=white)](https://hub.docker.com/u/libredevops)

---

## Contents

- [Overview](#overview)
- [Quick start](#quick-start)
- [Using this as a starting point](#using-this-as-a-starting-point)
- [Images](#images)
- [Choosing an image](#choosing-an-image)
- [Tags, versions and support](#tags-versions-and-support)
- [Usage](#usage)
- [Self-hosted CI agents](#self-hosted-ci-agents)
- [Podman in a container](#podman-in-a-container)
- [Configuration reference](#configuration-reference)
- [Adding an organisation's CA bundle](#adding-an-organisations-ca-bundle)
- [Pinning by digest or date tag](#pinning-by-digest-or-date-tag)
- [Security and supply chain](#security-and-supply-chain)
- [Built from source](#built-from-source)
- [Changing the base image](#changing-the-base-image)
- [Troubleshooting](#troubleshooting)
- [Developing](#developing)
- [Contributing](#contributing)
- [Licence](#licence)

## Overview

Eleven images, each a thin layer of pinned tools on a hardened base:

- **`python`**: CPython and uv, with one tag for every supported CPython from 3.12 upwards.
- **`ansible`**: ansible-core and ansible-lint in their own virtual environment, with
  jmespath, netaddr, pywinrm, OpenSSH (built from its latest release: see
  [Built from source](#built-from-source)) and uv. The current release, plus 2.16 for
  managing hosts whose only Python is 3.6 (see [Ansible](#ansible)).
- **`ansible-azure`**: the `ansible` image with the
  [azure.azcollection](https://galaxy.ansible.com/ui/repo/published/azure/azcollection/)
  collection and every Python library its modules need.
- **`azure-cli`**: the Azure CLI in its own virtual environment, and
  [`ldo-cli`](https://github.com/libre-devops/ldo-cli). The current release, plus 2.72.0 as a
  long-lived line.
- **`terraform`**: tenv with a default Terraform, TFLint, terraform-docs and Conftest. A
  repository's `.terraform-version` wins over the default. Also as an Alpine variant
  (`-alpine` tags), about a third smaller.
- **`azure-terraform`**: the `terraform` image with the azurerm, azapi and msgraph providers
  (the newest three minor releases of each) in a local mirror, so `terraform init` needs no
  registry for them (see [azure-terraform](#azure-terraform)).
- **`powershell`**: PowerShell LTS with PSScriptAnalyzer, Pester, Az, Microsoft.Graph and
  [LibreDevOpsHelpers](https://github.com/libre-devops/powershell-helpers).
- **`toolbox`**: Python, the Azure CLI, Terraform and PowerShell in one image, assembled from
  the same build stages.
- **`podman`**: Podman set up to run rootless inside a container (Podman in Podman, or in
  Docker or Kubernetes), with a `docker` command that runs it. `azure-cli`, `terraform` and
  `toolbox` also come as `-podman` flavours built on it, for CI jobs that build and push images
  (see [Podman in a container](#podman-in-a-container)).
- **`azure-pipelines-agent`** and **`github-runner`**: self-hosted CI agents that register
  themselves from environment variables and run one job per container. Each also comes as a
  `toolbox` flavour with every toolbox tool in it, and a `toolbox-podman` flavour that adds
  Podman, so jobs can build images (see [Self-hosted CI agents](#self-hosted-ci-agents)).

What every image guarantees:

| Property | How |
| --- | --- |
| Hardened base | [Docker Hardened Images](https://hub.docker.com/hardened-images/catalog) on Debian 13 (Alpine 3.24 for `-alpine` tags), pinned by digest |
| No known fixable vulnerabilities at publication | Scanned on every pull request, at release (the exact digest pushed) and daily after; fixes are applied at the source, not excused |
| Every input pinned | Bases by digest; downloads by version and SHA-256 per platform; Go modules through the Go checksum database; Python packages by hash |
| Reproducible references | Date tags are never overwritten; every tag has the same digest in GHCR and Docker Hub |
| Verifiable | cosign keyless signature, SBOM and SLSA provenance on every published digest |
| Non-root | Runs as `app` (uid 10001) in `/work`; works rootless under Podman, and as an arbitrary uid in group 0 |
| Multi-platform | linux/amd64 and linux/arm64, each built natively |
| Portable | The same build runs on RHEL (UBI), Wolfi and Alpine bases, proven on every pull request |
| Current | Rebuilt every Monday, on every merge, and whenever a published image can be fixed by a rebuild |

## Quick start

```sh
# Pull from either registry; the digest is the same.
docker pull ghcr.io/libre-devops/terraform:1
docker pull docker.io/libredevops/terraform:1

# Run against the current directory.
docker run --rm -v "$PWD:/work" ghcr.io/libre-devops/terraform:1 terraform fmt -check

# Verify the signature before you trust it.
cosign verify ghcr.io/libre-devops/terraform:1 \
  --certificate-identity https://github.com/libre-devops/container-images/.github/workflows/release.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Using this as a starting point

This repository is meant to be forked and owned: a working pipeline to start from, not a
finished product. To make it yours:

1. **Registries.** Set `registries` in [`versions.yml`](./versions.yml) to your GHCR
   organisation and Docker Hub namespace, and `REPOSITORY` in
   [`scripts/images.py`](./scripts/images.py) to your fork's URL. It goes into the image labels,
   the cosign signing identity and the Docker Hub overview.
2. **Secrets and settings.** Add `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` as repository
   secrets. They push to Docker Hub and pull the Docker Hardened Images bases from `dhi.io`,
   which needs an entitlement. Allow GitHub Actions to create pull requests (organisation and
   repository settings), and install Renovate.
3. **Bases.** Without a Docker Hardened Images entitlement, point `bases` at Red Hat UBI or
   Wolfi; the portability builds show every image works on them. `just pin` resolves the
   digests.
4. **Images.** Delete the images you do not need from `versions.yml`, with their stage in
   `images/Containerfile` and their `tests/` suite, and add your own the same way (see
   [Adding a version](#adding-a-version)).

Optional parts you can delete without breaking the rest:

| Part | Remove |
| --- | --- |
| The CI agents | Their entries in `versions.yml`, `images/agents/`, their stages and tests |
| Podman and the `-podman` flavours | The `podman` entry, the `base_stage: podman` lines, `images/podman/`, `tests/podman.sh` |
| `azure-terraform` | Its entry and `terraform_providers` in `versions.yml`, `images/terraform/` |
| The OpenSSH source build | Only the ansible images use it: switch them to `os_packages: [ssh]` (see [Built from source](#built-from-source)) |
| Portability builds | `portability` in `versions.yml`, and the portability job in the workflows |
| Automatic re-runs | `.github/workflows/retry.yml` |

Locally, `just build`, `just test`, `just scan` and `just lint` run the same steps CI does.

## Images

| Image | Tags | Base | Contents | Pull |
| --- | --- | --- | --- | --- |
| `python` | `3.12`<br>`3.12-YYYYMMDD` | `dhi.io/python:3.12-debian13-dev` | CPython 3.12, uv 0.13.7 | `ghcr.io/libre-devops/python:3.12`<br>`docker.io/libredevops/python:3.12` |
| `python` | `3.13`<br>`3.13-YYYYMMDD` | `dhi.io/python:3.13-debian13-dev` | CPython 3.13, uv 0.13.7 | `ghcr.io/libre-devops/python:3.13`<br>`docker.io/libredevops/python:3.13` |
| `python` | `3.14`<br>`3.14-YYYYMMDD` | `dhi.io/python:3.14-debian13-dev` | CPython 3.14, uv 0.13.7 | `ghcr.io/libre-devops/python:3.14`<br>`docker.io/libredevops/python:3.14` |
| `python` | `3.15` `3` `latest`<br>`3.15-YYYYMMDD` | `dhi.io/python:3.15-debian13-dev` | CPython 3.15, uv 0.13.7 | `ghcr.io/libre-devops/python:3.15`<br>`docker.io/libredevops/python:3.15` |
| `podman` | `5` `latest`<br>`5-YYYYMMDD` | `dhi.io/debian-base:trixie-debian13-dev` | Podman 5 from the distribution, with crun, fuse-overlayfs and a docker command, rootless for the app user | `ghcr.io/libre-devops/podman:5`<br>`docker.io/libredevops/podman:5` |
| `azure-cli` | `2.92.0` `latest`<br>`2.92.0-py3.12-YYYYMMDD` | `dhi.io/python:3.12-debian13-dev` | Azure CLI 2.92.0 on Python 3.12, ldo-cli 0.8.1 | `ghcr.io/libre-devops/azure-cli:2.92.0`<br>`docker.io/libredevops/azure-cli:2.92.0` |
| `azure-cli` | `2.92.0-podman` `podman`<br>`2.92.0-py3.12-podman-YYYYMMDD` | `dhi.io/python:3.12-debian13-dev` | Azure CLI 2.92.0 on Python 3.12, ldo-cli 0.8.1 | `ghcr.io/libre-devops/azure-cli:2.92.0-podman`<br>`docker.io/libredevops/azure-cli:2.92.0-podman` |
| `azure-cli` | `2.72.0`<br>`2.72.0-py3.12-YYYYMMDD` | `dhi.io/python:3.12-debian13-dev` | Azure CLI 2.72.0 on Python 3.12, ldo-cli 0.8.1 | `ghcr.io/libre-devops/azure-cli:2.72.0`<br>`docker.io/libredevops/azure-cli:2.72.0` |
| `terraform` | `1.17.1` `1.17` `1` `latest`<br>`1.17.1-YYYYMMDD` | `dhi.io/debian-base:trixie-debian13-dev` | Terraform 1.17.1 by default (tenv 4.15.1; a repository's .terraform-version wins), TFLint 0.65.0, terraform-docs 0.24.0, Conftest 0.71.1 | `ghcr.io/libre-devops/terraform:1.17.1`<br>`docker.io/libredevops/terraform:1.17.1` |
| `terraform` | `1.17.1-alpine` `1.17-alpine` `1-alpine` `alpine`<br>`1.17.1-alpine-YYYYMMDD` | `dhi.io/alpine-base:3.24-alpine3.24-dev` | Terraform 1.17.1 by default (tenv 4.15.1; a repository's .terraform-version wins), TFLint 0.65.0, terraform-docs 0.24.0, Conftest 0.71.1 | `ghcr.io/libre-devops/terraform:1.17.1-alpine`<br>`docker.io/libredevops/terraform:1.17.1-alpine` |
| `terraform` | `1.17.1-podman` `1.17-podman` `1-podman` `podman`<br>`1.17.1-podman-YYYYMMDD` | `dhi.io/debian-base:trixie-debian13-dev` | Terraform 1.17.1 by default (tenv 4.15.1; a repository's .terraform-version wins), TFLint 0.65.0, terraform-docs 0.24.0, Conftest 0.71.1 | `ghcr.io/libre-devops/terraform:1.17.1-podman`<br>`docker.io/libredevops/terraform:1.17.1-podman` |
| `ansible` | `2.22.0` `2.22` `latest`<br>`2.22.0-py3.14-YYYYMMDD` | `dhi.io/python:3.14-debian13-dev` | ansible-core 2.22.0 on Python 3.14, with ansible-lint, jmespath, netaddr, pywinrm, OpenSSH 10.6p2 and uv 0.13.7 | `ghcr.io/libre-devops/ansible:2.22.0`<br>`docker.io/libredevops/ansible:2.22.0` |
| `ansible` | `2.16.20` `2.16`<br>`2.16.20-py3.12-YYYYMMDD` | `dhi.io/python:3.12-debian13-dev` | ansible-core 2.16.20 on Python 3.12, for hosts whose only Python is 3.6 (RHEL 8): the last line that supports them. With ansible-lint, jmespath, netaddr, pywinrm, OpenSSH 10.6p2 and uv 0.13.7 | `ghcr.io/libre-devops/ansible:2.16.20`<br>`docker.io/libredevops/ansible:2.16.20` |
| `ansible-azure` | `4.2.0` `4` `latest`<br>`4.2.0-YYYYMMDD` | `dhi.io/python:3.14-debian13-dev` | azure.azcollection 4.2.0 and its Python requirements, on ansible-core 2.22.0 and Python 3.14, with ansible-lint, OpenSSH 10.6p2 and uv 0.13.7 | `ghcr.io/libre-devops/ansible-azure:4.2.0`<br>`docker.io/libredevops/ansible-azure:4.2.0` |
| `azure-terraform` | `1.17.1` `1.17` `1` `latest`<br>`1.17.1-YYYYMMDD` | `dhi.io/debian-base:trixie-debian13-dev` | Terraform 1.17.1 by default, TFLint 0.65.0, terraform-docs 0.24.0, Conftest 0.71.1; in a local provider mirror, azurerm 5.13.0, 5.12.0, 5.11.0, azapi 2.13.0, 2.12.0, 2.11.0 and msgraph 0.6.0, 0.5.0, 0.4.0 | `ghcr.io/libre-devops/azure-terraform:1.17.1`<br>`docker.io/libredevops/azure-terraform:1.17.1` |
| `powershell` | `7.6.9` `7.6` `7` `lts` `latest`<br>`7.6.9-YYYYMMDD` | `dhi.io/debian-base:trixie-debian13-dev` | PowerShell 7.6.9, Az 16.5.0, Microsoft.Graph 2.41.2, Pester 6.2.0, PSScriptAnalyzer 1.25.0, LibreDevOpsHelpers 3.0.1 | `ghcr.io/libre-devops/powershell:7.6.9`<br>`docker.io/libredevops/powershell:7.6.9` |
| `toolbox` | `1` `latest`<br>`1-YYYYMMDD` | `dhi.io/python:3.12-debian13-dev` | Python 3.12 and uv 0.13.7, Azure CLI 2.92.0, ldo-cli 0.8.1, Terraform 1.17.1 by default (tenv 4.15.1), TFLint 0.65.0, terraform-docs 0.24.0, Conftest 0.71.1, PowerShell 7.6.9 with Az 16.5.0, Microsoft.Graph 2.41.2, Pester 6.2.0, PSScriptAnalyzer 1.25.0 and LibreDevOpsHelpers 3.0.1 | `ghcr.io/libre-devops/toolbox:1`<br>`docker.io/libredevops/toolbox:1` |
| `toolbox` | `1-podman` `podman`<br>`1-podman-YYYYMMDD` | `dhi.io/python:3.12-debian13-dev` | Python 3.12 and uv 0.13.7, Azure CLI 2.92.0, ldo-cli 0.8.1, Terraform 1.17.1 by default (tenv 4.15.1), TFLint 0.65.0, terraform-docs 0.24.0, Conftest 0.71.1, PowerShell 7.6.9 with Az 16.5.0, Microsoft.Graph 2.41.2, Pester 6.2.0, PSScriptAnalyzer 1.25.0 and LibreDevOpsHelpers 3.0.1 | `ghcr.io/libre-devops/toolbox:1-podman`<br>`docker.io/libredevops/toolbox:1-podman` |
| `azure-pipelines-agent` | `5.281.1` `5` `latest`<br>`5.281.1-YYYYMMDD` | `dhi.io/debian-base:trixie-debian13-dev` | Azure Pipelines agent 5.281.1, with git, curl, jq, ShellCheck and shfmt | `ghcr.io/libre-devops/azure-pipelines-agent:5.281.1`<br>`docker.io/libredevops/azure-pipelines-agent:5.281.1` |
| `azure-pipelines-agent` | `5.281.1-toolbox` `5-toolbox` `toolbox`<br>`5.281.1-toolbox-YYYYMMDD` | `dhi.io/python:3.12-debian13-dev` | Azure Pipelines agent 5.281.1 with everything in toolbox 1: Azure CLI 2.92.0, Terraform 1.17.1, PowerShell 7.6.9 with Az and Microsoft.Graph, Python 3.12 | `ghcr.io/libre-devops/azure-pipelines-agent:5.281.1-toolbox`<br>`docker.io/libredevops/azure-pipelines-agent:5.281.1-toolbox` |
| `azure-pipelines-agent` | `5.281.1-toolbox-podman` `5-toolbox-podman` `toolbox-podman`<br>`5.281.1-toolbox-podman-YYYYMMDD` | `dhi.io/python:3.12-debian13-dev` | Azure Pipelines agent 5.281.1 with everything in toolbox 1 and Podman 5, which jobs can use to build and run images (rootless; see the README for the outer container's flags) | `ghcr.io/libre-devops/azure-pipelines-agent:5.281.1-toolbox-podman`<br>`docker.io/libredevops/azure-pipelines-agent:5.281.1-toolbox-podman` |
| `github-runner` | `2.338.2` `2` `latest`<br>`2.338.2-YYYYMMDD` | `dhi.io/debian-base:trixie-debian13-dev` | GitHub Actions runner 2.338.2, with git, curl, jq, ShellCheck and shfmt | `ghcr.io/libre-devops/github-runner:2.338.2`<br>`docker.io/libredevops/github-runner:2.338.2` |
| `github-runner` | `2.338.2-toolbox` `2-toolbox` `toolbox`<br>`2.338.2-toolbox-YYYYMMDD` | `dhi.io/python:3.12-debian13-dev` | GitHub Actions runner 2.338.2 with everything in toolbox 1: Azure CLI 2.92.0, Terraform 1.17.1, PowerShell 7.6.9 with Az and Microsoft.Graph, Python 3.12 | `ghcr.io/libre-devops/github-runner:2.338.2-toolbox`<br>`docker.io/libredevops/github-runner:2.338.2-toolbox` |
| `github-runner` | `2.338.2-toolbox-podman` `2-toolbox-podman` `toolbox-podman`<br>`2.338.2-toolbox-podman-YYYYMMDD` | `dhi.io/python:3.12-debian13-dev` | GitHub Actions runner 2.338.2 with everything in toolbox 1 and Podman 5, which jobs can use to build and run images (rootless; see the README for the outer container's flags) | `ghcr.io/libre-devops/github-runner:2.338.2-toolbox-podman`<br>`docker.io/libredevops/github-runner:2.338.2-toolbox-podman` |

Every image also has bash, git, curl, ca-certificates, ShellCheck 0.11.0, shfmt 3.14.1, jq 1.8.2, runs as `app` (uid 10001) in `/work`, and is a multi-platform image for linux/amd64 and linux/arm64. The Go tools are built from source with Go 1.27.3.

## Choosing an image

| If you need | Use | Why |
| --- | --- | --- |
| One tool family in a CI job | `python`, `ansible`, `azure-cli`, `terraform` or `powershell` | Smaller pulls, smaller attack surface, fewer reasons to rebuild |
| Terraform for Azure in an air-gapped or restricted network | `azure-terraform` | azurerm, azapi and msgraph install from a local mirror, with no registry |
| Ansible playbooks against Azure | `ansible-azure` | The Azure collection and its many Python libraries, already installed and patched |
| Ansible for hosts whose only Python is 3.6, such as RHEL 8 | `ansible:2.16` | ansible-core 2.17 and later cannot manage them; see [Ansible](#ansible) |
| Building and pushing images in a CI job, without Docker or a privileged container | `podman`, or a `-podman` flavour such as `azure-cli:podman` or `toolbox:podman` | Rootless Podman inside the container; see [Podman in a container](#podman-in-a-container) |
| Self-hosted Azure Pipelines agents or GitHub Actions runners | `azure-pipelines-agent`, `github-runner` | Ephemeral by default; the `toolbox` tags carry every toolbox tool |
| Several tool families in one job, or an interactive shell | `toolbox` | Everything together; the largest image (the Az PowerShell modules and the Azure CLI dominate its size) |
| A specific CPython | `python:<major.minor>` | One tag per supported CPython |
| The smallest Terraform image | `terraform:alpine` | About a third smaller than the Debian image. musl, so not for Azure Pipelines container jobs, which need glibc |
| The Azure CLI behind TLS inspection that rejects Python 3.13's stricter checks | `azure-cli:2.72.0` | Long-lived line on Python 3.12 |
| Your organisation's CA, mirrors or internal tools | A thin layer `FROM` a pinned digest of one of these | See [Adding an organisation's CA bundle](#adding-an-organisations-ca-bundle) |

## Tags, versions and support

| Tag | Example | Moves? |
| --- | --- | --- |
| Version and build date | `python:3.12-20261107`, `azure-cli:2.72.0-py3.12-20261107` | Never. A second build on the same day gets `.2`, `.3` and so on |
| Version | `python:3.12`, `azure-cli:2.72.0` | Yes, to the newest build of that version |
| Major or major.minor | `terraform:1`, `terraform:1.17`, `python:3`, `toolbox:1` | Yes |
| Alias | `powershell:lts` | Yes |
| Flavour | `terraform:1.17.1-alpine`, `terraform:1-alpine`, `terraform:alpine` | As above, with the flavour as a suffix; the flavour's own name is its newest version |
| `latest` | `python:latest` | Yes, to the newest supported version |

Every release records its digests in this README and in
[`releases.json`](./releases.json).

**What is built.** Every version listed in [`versions.yml`](./versions.yml):

| Image | Versions |
| --- | --- |
| `python` | Every CPython release from 3.12 upwards that upstream still supports |
| `ansible` | The current ansible-core, and 2.16 for managed hosts on Python 3.6 |
| `ansible-azure` | The current azure.azcollection, on the current `ansible` |
| `azure-cli` | The current release, and 2.72.0 as a long-lived line for networks whose TLS inspection fails the stricter certificate checks in Python 3.13 and later |
| `terraform` | The current Terraform 1.x as the default, on Debian and on Alpine; any other version through `.terraform-version` |
| `azure-terraform` | The current `terraform`, with the newest three minor releases of azurerm, azapi and msgraph |
| `powershell` | The current PowerShell LTS |
| `toolbox` | The latest `azure-cli`, `terraform` and `powershell`, with the Azure CLI's Python |
| `podman` | Podman 5 from the distribution, and `-podman` flavours of the latest `azure-cli`, `terraform` and `toolbox` |
| `azure-pipelines-agent`, `github-runner` | The current agent release, on its own, atop `toolbox`, and atop `toolbox` with Podman |

**Support.** A version is supported while it is listed in `versions.yml`: its moving tags are
rebuilt weekly and whenever a fix is available. When a version leaves `versions.yml` (for
example when upstream support ends), its tags stop moving and receive no further fixes, but
nothing published is ever deleted or re-tagged, so pinned references keep working.

## Usage

The examples use moving tags for brevity. For anything you need to reproduce, pin a date tag
or a digest (see [Pinning by digest or date tag](#pinning-by-digest-or-date-tag)).

### GitHub Actions

As a container job. The runner mounts the workspace and `HOME` as uid 1001, so run the job as
that uid in group 0; the images' home, work and tool directories are writable by group 0.

```yaml
jobs:
  plan:
    runs-on: ubuntu-26.04
    container:
      image: ghcr.io/libre-devops/terraform:1
      options: --user 1001:0
    steps:
      - uses: actions/checkout@v7
      - run: terraform init -backend=false && terraform validate
      - run: tflint --init && tflint
```

### GitLab CI

```yaml
test:
  image: ghcr.io/libre-devops/python:3.13
  script:
    - uv sync --locked
    - uv run pytest
```

### Azure DevOps

The Azure Pipelines agent adds its own user inside a container job, which needs root, so start
the container as root. `useradd` and `groupadd` are in every image for this.

```yaml
resources:
  containers:
    - container: azure
      image: ghcr.io/libre-devops/azure-cli:2.92.0
      options: --user 0:0

jobs:
  - job: deploy
    container: azure
    steps:
      - script: az version
```

Or run a single command with `docker run`, as your own uid so that files written to the
workspace stay yours:

```yaml
steps:
  - script: >-
      docker run --rm --user "$(id -u):0" -v "$(Build.SourcesDirectory):/work"
      ghcr.io/libre-devops/powershell:lts pwsh -File ./build.ps1
```

### azure-terraform

`terraform init` installs azurerm, azapi and msgraph from the image's own mirror, at
`/usr/local/share/terraform/providers`, and needs no registry for them; any other provider still
comes from the registry. The mirror holds the newest patch of each of the newest three minor
releases of each provider, each at least three days old, and the image tables above list
them. They move forward as new releases appear.

```sh
docker run --rm -v "$PWD:/work" ghcr.io/libre-devops/azure-terraform:1 terraform init
```

- **Constraints.** A configuration whose version constraints allow one of the mirrored
  versions, such as `~> 5.12` or `>= 5.0`, installs offline. One that pins a version the mirror
  lacks needs the registry.
- **Online, and a version the mirror lacks.** Terraform cannot fall back from the mirror to the
  registry by itself, so switch to the registry configuration:
  `TF_CLI_CONFIG_FILE=/usr/local/share/terraform/registry.tfrc`.
- **Lock files.** The mirror holds the release zips themselves, so a `.terraform.lock.hcl`
  made online matches them. Terraform reports mirrored providers as "unauthenticated" because
  it does not check signatures on local files: each zip's checksum was verified against the
  provider's signed release when it was pinned, and again when the image was built.
- **Other Terraform versions** from a `.terraform-version` still download on demand; set
  `TENV_AUTO_INSTALL=false` offline and use the default.
- **Terraform Stacks.** `terraform stacks` downloads its plugin, `tfstacks`, on first use, and
  always needs HCP Terraform or your Terraform Enterprise host (`TF_STACKS_HOSTNAME`). The image
  does not carry the plugin: its current release (1.4.0) is built with a Go version that has
  fixable high vulnerabilities, so it fails the scan gate.

### Ansible

Mount the playbooks and an SSH key, and run as your own uid so that what Ansible writes stays
yours:

```sh
docker run --rm --user "$(id -u):0" -v "$PWD:/work" -v "$HOME/.ssh:/home/app/.ssh:ro" \
  ghcr.io/libre-devops/ansible:2.22 ansible-playbook -i inventory.ini site.yml
```

Install collections per project from a `requirements.yml` with `ansible-galaxy collection
install -r requirements.yml`; they go to `~/.ansible/collections`. `ansible-azure` has
`azure.azcollection` installed for every user already, so authenticate the usual ways
(`AZURE_CLIENT_ID` and friends, a managed identity, or `~/.azure/credentials`). Azure modules
run on `localhost`, where they need Ansible's own Python, which has their libraries: that is
what Ansible uses for an implicit `localhost`. If your inventory lists `localhost`, give it
`ansible_python_interpreter: "{{ ansible_playbook_python }}"`.

**`ansible:2.16` is for one job only.** ansible-core runs Python on every host it manages,
and from 2.17 that must be Python 3.7 or newer. RHEL 8 and its rebuilds ship Python 3.6 as
the system (platform) Python, so the current ansible-core cannot manage them without first
installing a newer Python on each. The 2.16 line still can, and Renovate keeps it on 2.16
patch releases. Use it for those hosts, and the current line for everything else.

### Rootless Podman

`--userns=keep-id` maps your user to the image's uid 10001, so files in the mounted directory
are owned by you on both sides:

```sh
podman run --rm -it --userns=keep-id:uid=10001,gid=10001 \
  -v "$PWD:/work:Z" ghcr.io/libre-devops/terraform:1 terraform fmt -check
```

### Kubernetes and OpenShift

The images run as a non-root numeric uid, so `runAsNonRoot: true` is satisfied as is. An
arbitrary uid (OpenShift's default) works too, because the writable directories belong to
group 0:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

## Self-hosted CI agents

`azure-pipelines-agent` and `github-runner` register themselves when the container starts,
from environment variables, and are **ephemeral** by default: each runs one job, removes its
registration and exits, so every job starts from a clean image. Run them under anything that
restarts containers: a Kubernetes Deployment, a systemd unit, or `docker run --restart`. The
`toolbox` tags (`azure-pipelines-agent:toolbox`, `github-runner:toolbox`) add everything in
the `toolbox` image.

**Azure Pipelines.** A personal access token with the **Agent Pools (Read & manage)** scope
registers the agent; `AZP_TOKEN_FILE`, a mounted secret, keeps it out of the environment.

```sh
docker run -d --restart always \
  -e AZP_URL=https://dev.azure.com/contoso -e AZP_POOL=containers \
  -e AZP_TOKEN_FILE=/run/secrets/azp-token -v "$PWD/azp-token:/run/secrets/azp-token:ro" \
  ghcr.io/libre-devops/azure-pipelines-agent:toolbox
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `AZP_URL` | required | The organisation, such as `https://dev.azure.com/contoso` |
| `AZP_TOKEN` or `AZP_TOKEN_FILE` | required | The token, or a file holding it |
| `AZP_POOL` | `Default` | The agent pool |
| `AZP_AGENT_NAME` | the hostname | The agent's name |
| `AZP_WORK` | `_work` | The work directory, in `/opt/azure-pipelines-agent` |
| `AZP_EPHEMERAL` | `true` | `false` keeps the agent running jobs until the container stops |

**GitHub Actions.** Give the runner a registration token, a token that can create one, or a
just-in-time configuration (the API's `generate-jitconfig`, the best fit for autoscalers).

```sh
docker run -d --restart always \
  -e RUNNER_URL=https://github.com/contoso -e RUNNER_ACCESS_TOKEN \
  -e RUNNER_LABELS=containers \
  ghcr.io/libre-devops/github-runner:toolbox
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `RUNNER_URL` | required, unless `RUNNER_JIT_CONFIG` | `https://github.com/<org>` or `https://github.com/<owner>/<repo>`, or the same on GitHub Enterprise Server |
| `RUNNER_TOKEN` | | A registration token |
| `RUNNER_ACCESS_TOKEN` | | Creates registration tokens itself: a GitHub App installation token or a fine-grained token with Administration write (repository) or Self-hosted runners write (organisation) |
| `RUNNER_JIT_CONFIG` | | A just-in-time configuration; nothing else is needed |
| `RUNNER_NAME` | the hostname | The runner's name |
| `RUNNER_LABELS` | | Extra labels, comma-separated, on top of `self-hosted`, `linux` and the architecture |
| `RUNNER_GROUP` | | The runner group |
| `RUNNER_WORKDIR` | `_work` | The work directory, in `/opt/actions-runner` |
| `RUNNER_EPHEMERAL` | `true` | `false` keeps the runner running jobs until the container stops |

Things to know:

- **Updates come as images.** Neither agent updates itself. Renovate bumps them and a release
  follows, so keep pulling the moving tags: GitHub stops sending jobs to a runner 30 days after
  a newer release.
- **Jobs run as the agent's user**, so a job can read any credential the agent holds. Scope
  the tokens as above and nothing more.
- **No npm in the agents' own Node.** The agents run tasks with Node runtimes they bundle,
  and those come without npm, npx and corepack, which the agents never use and whose
  dependencies carry known vulnerabilities. A job that needs npm installs Node itself
  (`actions/setup-node`, or the `NodeTool` task).
- **Building images in jobs.** The `toolbox-podman` tags add rootless Podman and a `docker`
  command that runs it, so jobs can build, run and push images; start the agent with the flags
  in [Podman in a container](#podman-in-a-container). Container jobs and service containers,
  which the agents run through a Docker daemon, are not supported.
- **glibc only for the runner.** GitHub publishes no musl build, so there is no Alpine flavour.

## Podman in a container

Build, run and push images inside a CI job or a pod, with no Docker daemon, no Docker socket
and, on hosts that allow user namespaces, no `--privileged`. Podman runs **rootless**, as the
image's `app` user (uid 10001), inside the container.

| Image | Use it for |
| --- | --- |
| `podman:5` | Podman on its own, with a `docker` command that runs it |
| `azure-cli:podman`, `terraform:podman`, `toolbox:podman` | The image's tools, plus Podman |
| `azure-pipelines-agent:toolbox-podman`, `github-runner:toolbox-podman` | Self-hosted agents whose jobs build images |

Every one of them is tested on every pull request the same way: inside the container, as uid
10001, Podman pulls and runs an image, builds a new one, and runs that.

### What the outer container needs

| Where it runs | Start it with |
| --- | --- |
| Podman | `--device /dev/fuse`, and on SELinux hosts (RHEL, Fedora) `--security-opt label=disable` |
| Docker | `--device /dev/fuse --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined`, and `--security-opt label=disable` on SELinux hosts |
| Kubernetes | `/dev/fuse` and user namespaces: `privileged: true`, or a pod in its own user namespace with a device plugin for `/dev/fuse` (see [Kubernetes](#kubernetes)) |

Also:

- **Run as uid 10001.** Rootless Podman needs the user's subordinate ids, which `app` has. An
  arbitrary uid, such as OpenShift's, has none.
- **Ubuntu 23.10 and later hosts** keep unprivileged user namespaces from processes without an
  AppArmor profile, which includes Podman in a container. Allow them on the host:
  `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0` (or persist it in
  `/etc/sysctl.d/`).
- **Image storage.** Podman keeps images in `/home/app/.local/share/containers`. Mount a volume
  there to keep them between runs, or to keep them off the container's own filesystem.

### Examples

On a workstation or a build host:

```sh
# Podman on the host
podman run --rm --device /dev/fuse --security-opt label=disable \
  -v "$PWD:/work" ghcr.io/libre-devops/podman:5 \
  podman build -t registry.example.com/team/app:1 .

# Docker on the host
docker run --rm --device /dev/fuse --security-opt label=disable \
  --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  -v "$PWD:/work" ghcr.io/libre-devops/toolbox:podman \
  podman build -t registry.example.com/team/app:1 .
```

GitHub Actions, on a GitHub-hosted runner (Ubuntu, so allow user namespaces first). The job
needs `permissions: packages: write` to push to GHCR:

```yaml
steps:
  - uses: actions/checkout@v7
  - run: sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
  - env:
      TOKEN: ${{ secrets.GITHUB_TOKEN }}
      IMAGE: ghcr.io/example/app:${{ github.sha }}
    run: >-
      docker run --rm --device /dev/fuse --security-opt label=disable
      --security-opt seccomp=unconfined --security-opt apparmor=unconfined
      --security-opt systempaths=unconfined
      -v "$PWD:/work" -e TOKEN -e IMAGE ghcr.io/libre-devops/podman:5
      bash -c 'echo "$TOKEN" | podman login ghcr.io -u token --password-stdin &&
               podman build -t "$IMAGE" . && podman push "$IMAGE"'
```

A self-hosted Azure Pipelines agent whose jobs can build images (see
[Self-hosted CI agents](#self-hosted-ci-agents) for its settings):

```sh
docker run -d --restart always --device /dev/fuse --security-opt label=disable \
  --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  -e AZP_URL=https://dev.azure.com/contoso -e AZP_POOL=containers \
  -e AZP_TOKEN_FILE=/run/secrets/azp-token -v "$PWD/azp-token:/run/secrets/azp-token:ro" \
  ghcr.io/libre-devops/azure-pipelines-agent:toolbox-podman
```

Jobs then run `podman build`, or `docker build`, as plain script steps.

### Kubernetes

Three manifests in [`examples/kubernetes/`](./examples/kubernetes), each checked against the
Kubernetes 1.33 and 1.34 API schemas:

| File | What it is |
| --- | --- |
| [`podman-build-job.yaml`](./examples/kubernetes/podman-build-job.yaml) | A Job that clones a repository, builds and pushes, privileged: works on most clusters |
| [`podman-build-job-user-namespaces.yaml`](./examples/kubernetes/podman-build-job-user-namespaces.yaml) | The same Job without `privileged`, in the pod's own user namespace (`hostUsers: false`, Kubernetes 1.33 and later) with `/dev/fuse` from a device plugin |
| [`azure-pipelines-agent-podman.yaml`](./examples/kubernetes/azure-pipelines-agent-podman.yaml) | A Deployment of ephemeral Azure Pipelines agents whose jobs can build images |

The core of the first:

```yaml
spec:
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
      containers:
        - name: build
          image: ghcr.io/libre-devops/podman:5
          command: ["bash", "-c", "git clone --depth 1 \"$REPOSITORY\" /work/src && podman build -t \"$IMAGE\" /work/src && podman push \"$IMAGE\""]
          env:
            - name: REGISTRY_AUTH_FILE
              value: /run/secrets/registry/auth.json
          securityContext:
            privileged: true
            runAsNonRoot: true
            runAsUser: 10001
            runAsGroup: 10001
          volumeMounts:
            - name: containers
              mountPath: /home/app/.local/share/containers
```

`privileged` is what most clusters need: it gives the container `/dev/fuse` and lets Podman
create its user namespace. Podman still runs as uid 10001 inside it. Where the cluster runs pods
in their own user namespace, the second manifest removes `privileged`: the pod's root then maps
to an unprivileged user on the node. Pod Security Admission's `restricted` and `baseline`
levels reject both, so run them in a namespace labelled `privileged`.

### What works, and what does not

- **Works:** `podman build`, `run`, `push`, `pull`, `login` and `save`; multi-stage builds;
  `docker build` and the other `docker` commands, through the `docker` command that runs Podman.
- **Network:** nested containers share the outer container's network, so builds reach whatever
  the job can reach.
- **Does not work:** tools that talk to a Docker daemon over its socket (Testcontainers,
  docker-compose against `/var/run/docker.sock`), and the CI agents' container jobs and service
  containers, which need a real Docker daemon.

### How it works

- `app` has subordinate uids and gids 1 to 65535 apart from its own, which fits inside the 65536
  ids a rootless outer container usually maps.
- `newuidmap` and `newgidmap` carry file capabilities instead of the setuid bit. A setuid
  `newuidmap` cannot write a nested container's id map; this is what Red Hat's
  `quay.io/podman/stable` does too.
- Storage goes through fuse-overlayfs, since the kernel's overlay cannot mount over the outer
  container's own overlay. Newer Buildah overlays the build context as well.
- Nested containers share the outer container's namespaces and need no cgroups
  (`/etc/containers/containers.conf`), and builds isolate `RUN` steps with chroot
  (`BUILDAH_ISOLATION=chroot`): a container cannot create most namespaces of its own.

## Configuration reference

### User and paths

| Path | Purpose | Writable by |
| --- | --- | --- |
| `/home/app` | `HOME` for every user the image runs as | `app`, and any uid in group 0 |
| `/work` | Working directory; mount your project here | `app`, and any uid in group 0 |
| `/opt/az` | The Azure CLI's virtual environment (`azure-cli`, `toolbox`) | root |
| `/opt/ldo-cli` | ldo-cli's virtual environment (`azure-cli`, `toolbox`) | root |
| `/opt/microsoft/powershell/7` | PowerShell (`powershell`, `toolbox`) | root |
| `/usr/local/share/powershell/Modules` | Pinned PowerShell modules, for all users | root |
| `/home/app/.tenv` | tenv's Terraform installs (`TENV_ROOT`) | `app`, and any uid in group 0 |
| `/opt/ansible` | Ansible's virtual environment (`ansible`, `ansible-azure`) | root |
| `/usr/local/share/terraform` | The provider mirror and the two CLI configurations (`azure-terraform`) | root |
| `/usr/share/ansible/collections` | Collections for every user (`ansible-azure`) | root |
| `/opt/azure-pipelines-agent`, `/opt/actions-runner` | The agents, their registration and their work (`azure-pipelines-agent`, `github-runner`) | `app`, and any uid in group 0 |

### Environment

Set by the images; override any of them with `-e` or your CI system's environment settings.

| Variable | Value | Image | Effect |
| --- | --- | --- | --- |
| `HOME` | `/home/app` | all | Consistent home for any uid |
| `REQUESTS_CA_BUNDLE` | `/etc/ssl/certs/ca-certificates.crt` | all | Python `requests` (and the Azure CLI) use the system trust store |
| `NODE_EXTRA_CA_CERTS` | `/etc/ssl/certs/ca-certificates.crt` | all | Node.js, which the CI agents run tasks with, trusts the system store too |
| `UV_NATIVE_TLS` | `true` | all | uv uses the system trust store rather than its own |
| `LANG` | `C.UTF-8` | `ansible`, `ansible-azure` | ansible-core refuses to run without a UTF-8 locale |
| `BUILDAH_ISOLATION` | `chroot` | `podman`, `-podman` flavours | `podman build` isolates `RUN` steps with chroot, which works inside a container |
| `TF_CLI_CONFIG_FILE` | `/usr/local/share/terraform/airgapped.tfrc` | `azure-terraform` | Mirrored providers install from the mirror; `registry.tfrc` uses the registry for everything |
| `PYTHONUNBUFFERED` | `1` | `python`, `azure-cli`, `toolbox` | Unbuffered output in CI logs |
| `AZURE_CORE_COLLECT_TELEMETRY` | `no` | `azure-cli`, `toolbox` | No Azure CLI telemetry |
| `TENV_ROOT` | `/home/app/.tenv` | `terraform`, `toolbox` | Where tenv keeps Terraform versions |
| `TENV_AUTO_INSTALL` | `true` | `terraform`, `toolbox` | A `.terraform-version` installs on demand; set `false` offline |
| `CHECKPOINT_DISABLE` | `1` | `terraform`, `toolbox` | No HashiCorp update checks |
| `POWERSHELL_TELEMETRY_OPTOUT` | `1` | `powershell`, `toolbox` | No PowerShell telemetry |
| `POWERSHELL_UPDATECHECK` | `Off` | `powershell`, `toolbox` | No update notices |
| `DOTNET_CLI_TELEMETRY_OPTOUT`, `DOTNET_NOLOGO` | `1` | `powershell`, `toolbox` | No .NET telemetry or banners |

git trusts every directory (`safe.directory = *` in the system configuration), because CI
systems mount workspaces owned by other uids.

## Adding an organisation's CA bundle

Networks with TLS inspection need their root CA in the image. Build a thin layer `FROM` a
pinned digest of these images, add the certificate with `add-ca-certificates`, and switch
back to the app user:

```Dockerfile
FROM ghcr.io/libre-devops/azure-cli:2.92.0@sha256:<digest>
USER root
COPY organisation-root-ca.pem /tmp/organisation-root-ca.pem
RUN add-ca-certificates /tmp/organisation-root-ca.pem && rm /tmp/organisation-root-ca.pem
USER 10001:10001
```

That is all. `add-ca-certificates` works on every base (Debian, Alpine, RHEL and Wolfi), takes
files holding one or several PEM certificates, and adds them to the system trust store, which
every tool in the images uses:

| Tool | Trusts the system store through |
| --- | --- |
| curl, git, Terraform and the Go tools, PowerShell and .NET | The operating system's TLS libraries |
| The Azure CLI, ldo-cli and Ansible | [pip-system-certs](https://pypi.org/project/pip-system-certs/), installed in each of their virtual environments |
| Python `requests` in your own environments | `REQUESTS_CA_BUNDLE` |
| pip | Its built-in use of the system store (pip 24.2 and later) |
| uv | `UV_NATIVE_TLS=true` |
| Node.js, and the CI agents' tasks | `NODE_EXTRA_CA_CERTS` |

The system bundle is `/etc/ssl/certs/ca-certificates.crt` on every base (a link to
`/etc/pki/tls/certs/ca-bundle.crt` on RHEL). Every pull request proves all of the above: the
smoke tests add a throwaway CA and check each client against a server it signed.

## Pinning by digest or date tag

Moving tags (`3.12`, `1`, `latest`) follow each rebuild. If you cannot refresh a tag you
already pulled, or need a build to be reproducible, pin a date tag, which is never
overwritten, or a digest, which is the same in GHCR and Docker Hub:

```text
ghcr.io/libre-devops/python:3.12-20261107
docker.io/libredevops/python@sha256:<digest>
```

Renovate and Dependabot both update digest pins in your own repositories.

The newest digest of every version, as of the last release:

| Image | Version | Newest date tag | Digest | Released |
| --- | --- | --- | --- | --- |
| `python` | `3.12` | `3.12-20261114` | `sha256:e1776e9e2ec6cab5fb2dea129720959bcbe37f032701ef84af2d813e5b071604` | 2026-11-14 |
| `python` | `3.13` | `3.13-20261114` | `sha256:d048c9d71d25c9c0b0ecc24923afd6d6ba65e39039def41ec6b36441a476c5ed` | 2026-11-14 |
| `python` | `3.14` | `3.14-20261114` | `sha256:55e940478d42974d9696e5499fa8d0d65f47c37b24f8e85d2430c1549a83c550` | 2026-11-14 |
| `python` | `3.15` | `3.15-20261114` | `sha256:a8ab84ab5f622c8b15956ed6094bc3828e258bf76b99f935e9e55de4355c3437` | 2026-11-14 |
| `azure-cli` | `2.92.0` | `2.92.0-py3.12-20261114` | `sha256:325db039c35b8872cee078030f5f84752d9c69efd2424b97180ae70cab6d8ea9` | 2026-11-14 |
| `azure-cli` | `2.72.0` | `2.72.0-py3.12-20261114` | `sha256:a3e7274987ee3c68e31b1d2d05160edd8203b7f522b02c51e046e0f612bb8b07` | 2026-11-14 |
| `terraform` | `1.17.1` | `1.17.1-20261114` | `sha256:2365241657fb858b29d918858cdc9b66b19661419da4242ca88ffc3a49862967` | 2026-11-14 |
| `terraform` | `1.17.1-alpine` | `1.17.1-alpine-20261114` | `sha256:94d535d80d11f3cab26dd723d0385abe111115a69dba96a65fa309d8b424d5cf` | 2026-11-14 |
| `ansible` | `2.22.0` | `2.22.0-py3.14-20261114` | `sha256:3c4311977de141a9ba461f479545c8d5d83fa22feb96ea3e034367de59bfd1e4` | 2026-11-14 |
| `ansible` | `2.16.20` | `2.16.20-py3.12-20261114` | `sha256:91b35d38aefe16c41d1c701283e76a56bb8e712a6b5bcc19b2e27423aeb1bb8e` | 2026-11-14 |
| `ansible-azure` | `4.2.0` | `4.2.0-20261114` | `sha256:a114458b1dcbc1aab7f88496e0534171f8e4d42c24d14d104b3f7626e0e92ee9` | 2026-11-14 |
| `azure-terraform` | `1.17.1` | `1.17.1-20261114` | `sha256:23ebaa6ee8314024d523c541899a4731c79708b8526ad438e2127308d1bc5963` | 2026-11-14 |
| `powershell` | `7.6.9` | `7.6.9-20261114` | `sha256:0491134492eb81e2054751bd34759973f85d11476ae8778280673750e4d8616c` | 2026-11-14 |
| `toolbox` | `1` | `1-20261114` | `sha256:2cfe86a54787c677a7b5cb1c5987c3e4ccc268051abe204dc3a914d0df44002e` | 2026-11-14 |
| `azure-pipelines-agent` | `5.281.1` | `5.281.1-20261114` | `sha256:d1fad2f1674ea6827afdcb5607ad828de06ef6e4b72501cee18212514bee8c12` | 2026-11-14 |
| `azure-pipelines-agent` | `5.281.1-toolbox` | `5.281.1-toolbox-20261114` | `sha256:deeab257c3b260d74c7c0fdf6a181078682d2a4f7bf21bf2a45742f83ec28014` | 2026-11-14 |
| `github-runner` | `2.338.2` | `2.338.2-20261114` | `sha256:432214b255517aeda1675fc5ca27a59ec5af52b6fbb875af8ec02c8aced6dba7` | 2026-11-14 |
| `github-runner` | `2.338.2-toolbox` | `2.338.2-toolbox-20261114` | `sha256:4619922ed56a9426b056f91baafe45bad773cf4db26c6caa608fba6634fcde15` | 2026-11-14 |

## Security and supply chain

Security problems are found as early as possible and fixed at the source.

```mermaid
flowchart LR
  subgraph pr["Every pull request"]
    check["Validate pins, lint, zizmor, actionlint, Trivy repository scan"] --> build["Build every version, amd64 and arm64"]
    build --> test["Smoke tests"] --> gate["Trivy gate"]
    check --> port["Build on UBI, Wolfi and Alpine bases"]
  end
  subgraph release["Release: merges, Mondays, on demand"]
    push["Build once per platform, push by digest"] --> verify["Smoke test and scan that digest"]
    verify --> tag["Tag GHCR and Docker Hub from one manifest"] --> sign["Check digests match, sign with cosign"]
  end
  subgraph daily["Every day"]
    pins["Pins: base digests, OSV patches, Python locks"] --> prs["Pull request, built, tested, merged"]
    scan["Scan every published image"] --> tab["Security tab"]
  end
  gate --> push
  prs --> push
  scan -- "fails the gate" --> push
```

### Controls

- **Before anything is built.** Every pull request lints the workflows for security problems
  with [zizmor](https://docs.zizmor.sh) (template injection, excessive permissions, persisted
  credentials, unpinned actions) and for correctness with actionlint, scans the repository for
  secrets and misconfigurations with Trivy, and lints the Containerfile and every script.
- **Least privilege in CI.** Every workflow starts from `permissions: {}` and grants each job
  only what it needs. Every action is pinned by commit SHA. No checkout persists credentials.
- **Go tools built from source.** shfmt, tenv, TFLint, terraform-docs and Conftest are built
  with the pinned, current Go rather than downloaded, so they carry no old toolchain's
  vulnerabilities. `just lock` checks every dependency of each against [OSV](https://osv.dev)
  and records the fixed version of any that is vulnerable; the build raises it, never lowering
  anything. Sources and dependencies are verified against the Go checksum database.
- **Python dependencies hash-locked and patched.** The Azure CLI and ldo-cli install from
  locks in `images/locks/` that pin every package by version and SHA-256, with any package OSV
  knows to be vulnerable raised to a fixed version.
- **Scanning before publishing.** Trivy scans every image on every pull request and scans the
  exact pushed digest on every release. A critical finding, or a high one with a fix available,
  fails the build and nothing is tagged.
- **Scanning after publishing.** Every day, the Scan workflow rescans every published image,
  reports every finding in the repository's Security tab, and starts a rebuild if a published
  image fails the gate.
- **Fixes as soon as they exist.** Every day, the Pins workflow re-resolves the base images,
  re-audits every pinned dependency and opens a pull request with any fix, which merges itself
  and releases once Build passes. Renovate raises security updates immediately, outside its
  weekly schedule, and merges any update but a major one once its checks pass.

### Vulnerability handling policy

A finding is resolved by removing it: a newer base, a patched dependency, or a newer tool.
Where a scanner reports something that does not apply, it is set aside only by a VEX statement
that says why:

| Source | What it covers |
| --- | --- |
| The base image's publisher | Docker Hardened Images attach signed [OpenVEX](https://openvex.dev) statements to every image, recording packages they have patched in place or that are not affected. The scan applies the statements attached to the pinned base digest, and no others. |
| This repository, [`vex/libre-devops.openvex.json`](./vex/libre-devops.openvex.json) | Findings examined here and shown not to apply, each with its justification. Reviewed in pull requests like any other change. |

Time-boxed exceptions go in [`.trivyignore.yaml`](./.trivyignore.yaml) with a reason and an
expiry date, after which the finding fails the gate again. In force:

| Findings | Where | Why accepted | Expires |
| --- | --- | --- | --- |
| Seven high CVEs in .NET runtime 10.0.12 and System.Security.Cryptography.Pkcs 9.0.10 | The Azure Pipelines agent's bundled .NET (`azure-pipelines-agent`) | Only Microsoft can update them, in an agent release; these findings apply | 2026-12-13 |
| CVE-2026-114149 in Microsoft.AspNetCore.WebUtilities 8.0.25 | The GitHub Actions runner's bundled libraries (`github-runner`) | Only GitHub can update it, in a runner release; this finding applies | 2026-12-13 |

Renovate brings in each agent release as it appears; an exception whose finding is gone has no
effect, and is removed.

### Verifying an image

Every published digest is signed by the Release workflow on `main`, in both registries, and
carries an SBOM and SLSA provenance as attestations. The signature covers the image index, and
with it the attestations it references.

```sh
# Signature
cosign verify ghcr.io/libre-devops/python:3.13 \
  --certificate-identity https://github.com/libre-devops/container-images/.github/workflows/release.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

# SBOM and provenance
docker buildx imagetools inspect ghcr.io/libre-devops/python:3.13 --format '{{ json .SBOM }}'
docker buildx imagetools inspect ghcr.io/libre-devops/python:3.13 --format '{{ json .Provenance }}'

# The same digest in both registries
for r in ghcr.io/libre-devops docker.io/libredevops; do
  docker buildx imagetools inspect "$r/python:3.13" --format '{{ json .Manifest }}' | jq -r .digest
done
```

To report a vulnerability, see [SECURITY.md](./SECURITY.md).

## Built from source

Everything in the images comes from the distribution's packages or a pinned upstream release,
except what is listed here. Each is built from its latest signed or checksummed release, which
Renovate bumps, because the packaged version lags behind a security fix; each goes back to the
package once that catches up.

| What | Images | Why | Back to the package when |
| --- | --- | --- | --- |
| OpenSSH client (`ssh`, `scp`, `sftp`, `ssh-keygen` and friends), from its signed release | `ansible`, `ansible-azure` | Debian 13's `openssh-client` lacked the fix for CVE-2026-60002 (critical, fixed in OpenSSH 10.4) on 2026-11-13 | The base's `openssh-client` passes the scan gate: use `os_packages: [ssh]` and remove the `openssh` stage |
| shfmt, tenv, TFLint, terraform-docs, Conftest | all, `terraform`, `toolbox` | Built with the current Go and patched dependencies by design, not as a stopgap (see [Controls](#controls)) | Not planned |

## Changing the base image

The published images build on Docker Hardened Images, but nothing in the build depends on
that. A base needs only:

- glibc or musl. On musl (Alpine), uv and PowerShell use their musl builds and everything
  else is a static binary, so every image builds, with one exception: Microsoft publishes no
  musl build of PowerShell for arm64, so `powershell` and `toolbox` are amd64 only on musl,
- a POSIX shell at `/bin/sh`,
- one of `apt-get`, `dnf`, `microdnf` or `apk`.

Every image is a target in one multi-stage [`images/Containerfile`](./images/Containerfile).
Package installs go through `images/common/os-packages.sh`, which maps logical names to each
package manager's; the user is created by writing the account files directly; tools are pinned
downloads or built from source; and if the base lacks the requested CPython, uv installs it.
The CPython uv installs comes without the pip it bundles, whose vendored libraries lag behind
their security fixes: use `uv pip`, and virtual environments get a current pip of their own.

To build on another base locally, name a key from `versions.yml` or give a full reference:

```sh
just test terraform "" rhel-minimal
just build python 3.13 registry.access.redhat.com/ubi10/ubi:10.1@sha256:<digest>
```

To publish on another base, change the entries under `bases` in `versions.yml` and run
`just pin`. To publish an extra variant on another base, as the `-alpine` tags are, add a
version line with a `flavour` (see `versions.yml`). The portability bases (UBI 10, UBI 10
minimal, Wolfi and Docker Hardened Images Alpine) are built and smoke tested on every pull
request, so either edit stays safe. If a hardened variant you need does not exist,
`docker.io/library/debian:13-slim`, pinned by digest, is a drop-in fallback.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Permission denied` writing to the workspace in a GitHub Actions container job | The runner's workspace belongs to uid 1001 | Add `options: --user 1001:0` to the container |
| Files created in a mounted directory are owned by uid 10001 on the host | The container ran as `app` | `docker run --user "$(id -u):0"`, or `podman run --userns=keep-id:uid=10001,gid=10001` |
| `certificate verify failed` or `self-signed certificate in certificate chain` | TLS inspection with a CA the image does not trust | [Add your organisation's CA bundle](#adding-an-organisations-ca-bundle) |
| A `.terraform-version` fails to install in a network without internet access | tenv downloads it from HashiCorp | Use the default Terraform with `TENV_AUTO_INSTALL=false`, or point tenv at an internal mirror |
| `toomanyrequests` pulling from Docker Hub | Docker Hub's anonymous pull limits | Pull the same digest from `ghcr.io/libre-devops` |
| A container job in Azure Pipelines fails before the first step | The agent could not add its user | Start the container as root: `options: --user 0:0` |
| An `-alpine` image fails as an Azure Pipelines container job | The agent's Node.js needs glibc, and Alpine uses musl | Use the Debian tags (the ones without `-alpine`) |
| `Import-Module Az` is slow | Az loads every service module | Import only what you use, for example `Import-Module Az.Accounts, Az.Resources` |
| `Import-Module Microsoft.Graph` is slow | It loads about forty modules | Import only what you use, for example `Import-Module Microsoft.Graph.Users` |
| `azure-terraform`: `Failed to query available provider packages` or `no available releases match` for azurerm, azapi or msgraph | The constraints exclude every mirrored version | Loosen the constraint, or use the registry: `TF_CLI_CONFIG_FILE=/usr/local/share/terraform/registry.tfrc` |
| Ansible fails on a RHEL 8 host with a Python version error | ansible-core 2.17 and later need Python 3.7 or newer on the host | Use `ansible:2.16` for those hosts |
| `crun: mount proc to proc: Operation not permitted` from Podman in a container | Docker masks parts of `/proc`, and the kernel then refuses nested containers their own | Add `--security-opt systempaths=unconfined` (Docker) or `--security-opt unmask=ALL` (Podman) |
| `newuidmap: write to uid_map failed` or `cannot set up namespace` from Podman in a container | User namespaces are blocked: Docker's seccomp or AppArmor profile, or Ubuntu's `apparmor_restrict_unprivileged_userns` | Start the container with the flags in [Podman in a container](#podman-in-a-container), and on Ubuntu hosts set the sysctl there |
| `fuse: device not found` from Podman in a container | No `/dev/fuse` | Add `--device /dev/fuse` |
| A self-hosted runner gets no jobs | GitHub stops sending jobs to a runner 30 days after a newer release | Pull the moving tag again; new runner versions are released automatically |

## Developing

You need Docker or Podman, [just](https://just.systems) and [uv](https://docs.astral.sh/uv/).
`just tools` installs the pinned linters and Trivy into `.tools`.

| Recipe | Does |
| --- | --- |
| `just build <image> [version] [base]` | Build for this machine, with CI's build arguments (a flavour is a version: `just build terraform 1.17.1-alpine`) |
| `just test <image> [version] [base]` | Build, then run the smoke tests |
| `just scan <image> [version] [base]` | Build, then scan with the release gate |
| `just docs` / `just docs-check` | Write README.md, or fail if it is out of date |
| `just lock` | Pin new downloads and patch known vulnerabilities |
| `just pin` | Re-resolve every base image tag to its current digest |
| `just validate` | Check `versions.yml`, the lock and the base pins |
| `just lint` | hadolint, ShellCheck, shfmt, actionlint, zizmor, Trivy and the text rules |
| `just snapshot <dir>` | Record every package and tag in both registries |

### Workflows

| Workflow | Runs on | Does | Publishes |
| --- | --- | --- | --- |
| [Build](./.github/workflows/build.yml) | Every pull request; started by Pins and Release | Check, build every version for both platforms, smoke test, scan; portability builds; merge the pull requests Pins and Release open, once they pass | No |
| [Release](./.github/workflows/release.yml) | Merges to `main` that change the images, not only docs or workflows (Build starts it after merging the pins refresh), Mondays 03:00 UTC, on demand, and Scan | Build once per platform, test and scan the pushed digest, tag both registries, sign, open a pull request with the new digests | Yes |
| [Pins](./.github/workflows/pins.yml) | Pull requests that change `versions.yml`; daily 02:00 UTC | Repin and patch on the branch and re-run Build; daily, refresh base digests and patches as a pull request, and re-run Build on it | No |
| [Scan](./.github/workflows/scan.yml) | Daily 06:00 UTC | Rescan every published image, report to the Security tab, rebuild if needed | No |
| [Retry](./.github/workflows/retry.yml) | A Build, Release, Pins or Scan run that fails | Re-run its failed jobs once, so a flaky registry or network heals by itself; a second failure stands | No |

### Adding a version

Add one line under the image's `versions` in `versions.yml` (and, for a new CPython, a line
under `bases`), then run `just lock pin docs`, or push the branch and let the Pins workflow do
it. The CI matrix, tags, tests and README follow from `versions.yml`.

### How the pins stay current

| Pin | Lives in | Kept current by |
| --- | --- | --- |
| Tool and image versions | `versions.yml` | Renovate: weekly, and at once for a security fix |
| SHA-256 of every download, per platform | `versions.lock.json` | The Pins workflow, on every pull request branch in this repository that changes `versions.yml` |
| Fixed versions of vulnerable Go dependencies | `versions.lock.json` | The Pins workflow, on those branches and every day |
| Hash-locked Python dependencies | `images/locks/` | The Pins workflow, on those branches and every day |
| Base image digests | `versions.yml` | The Pins workflow, every day, as a pull request that merges itself once Build passes |
| Terraform providers in `azure-terraform` | `versions.yml` (`terraform_providers`), and their SHA-256 in `versions.lock.json` | The Pins workflow, every day: the newest three minor releases, each pinned once its signed checksums verify |
| GitHub Actions | the workflows, by commit SHA | Renovate |

A download pin, once written, is never re-fetched: an upstream asset that changes after it was
pinned fails the build rather than being trusted. Vulnerability patches, by contrast, are
recomputed on every run, so a newly published advisory is acted on the next day. Because a
push made with `GITHUB_TOKEN` does not trigger workflows, the Pins workflow starts the Build
workflow on the commit it pushes.

### Layout

```text
versions.yml            The single source: images, versions, tags, bases
versions.lock.json      Generated: download SHA-256s, Go dependency fixes, Python locks
releases.json           Generated by releases: the newest digest of every version
images/Containerfile    One multi-stage build; every image is a target
images/common/          Distribution-neutral build steps shared by every image
images/<image>/         An image's own install steps
images/locks/           Generated: hash-locked Python requirements
vex/                    VEX statements for findings shown not to apply
examples/kubernetes/    Kubernetes manifests for Podman in a container
tests/                  Smoke tests, run in every image as the app user
scripts/                Matrix, tags, pins, VEX and docs (images.py), and CI helpers
.github/workflows/      Build, Release, Pins and Scan
```

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](./CONTRIBUTING.md) for the workflow and
conventions, and [SECURITY.md](./SECURITY.md) to report a vulnerability privately.

## Licence

[MIT](./LICENSE)
