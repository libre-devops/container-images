# Security policy

## Reporting a vulnerability

Report vulnerabilities privately through
[GitHub's private vulnerability reporting](https://github.com/libre-devops/container-images/security/advisories/new),
never in a public issue or pull request. Include:

- the image, and the tag or digest,
- what you found and how to reproduce it,
- the impact as you understand it.

You will get an acknowledgement within a week, and progress updates until the report is
resolved. Fixes are released as soon as they pass the pipeline, and published advisories credit
the reporter unless asked not to.

A vulnerability in a tool an image contains (the Azure CLI, Terraform, PowerShell and so on)
belongs with that tool's maintainers. Report it here as well if the way an image installs or
configures the tool introduces or worsens it.

## Scope

In scope: the published images, everything in this repository that builds them (the
Containerfile, scripts and workflows), and the release and signing process.

Out of scope: vulnerabilities in upstream tools with no fix released (they are tracked, and
fixed as soon as a fix exists), and layers you build on top of these images.

## Supported versions

| Version | Supported |
| --- | --- |
| Every image version listed in [`versions.yml`](./versions.yml), through its moving tags | Yes: rebuilt weekly and whenever a fix is available |
| Date tags (`3.12-20261107`) | Kept for reproducibility; not patched in place. Move to the newest date tag or the moving tag |
| Versions removed from `versions.yml` | No. Published tags remain, but receive no fixes |

## How vulnerabilities are kept out

- Every input is pinned: base images by digest, downloads by version and SHA-256 per platform,
  Go modules through the Go checksum database, Python packages by hash.
- Go tools are built from source with the current Go, with every dependency that has a known
  vulnerability raised to its fixed version. Python dependencies are locked and patched the same
  way. Both are re-audited against [OSV](https://osv.dev) every day.
- Every image is scanned with Trivy on every pull request, at release (the exact digest pushed)
  and daily after publication. A critical finding, or a high one with a fix available, blocks
  publication, and a published image that fails the gate is rebuilt.
- Findings are fixed, not excused. A finding is set aside only by a VEX statement: the signed
  statements the base image's publisher attaches to the pinned digest, or a reviewed statement
  in [`vex/libre-devops.openvex.json`](./vex/libre-devops.openvex.json) with its justification.
- Workflows run with least privilege, every action is pinned by commit SHA, and workflows are
  audited with zizmor on every change.

## Verifying what you run

Every published digest is signed with cosign keyless signing by the Release workflow on
`main`, and carries an SBOM and SLSA provenance. The README's
[Verifying an image](./README.md#verifying-an-image) section shows the commands.
