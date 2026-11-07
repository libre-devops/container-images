# Contributing

Thank you for helping. Issues and pull requests are welcome. To report a vulnerability, follow
[SECURITY.md](./SECURITY.md) instead of opening an issue.

## Workflow

1. Open an issue first for anything larger than a fix, so the approach can be agreed.
2. Branch from `main` and keep each pull request to one change.
3. Run the checks below, and fill in the pull request template.
4. The Build workflow must pass, and a maintainer reviews every change. Merging releases.

## Checks

```sh
just tools                   # pinned hadolint, ShellCheck, shfmt, actionlint, zizmor and Trivy, into .tools
just validate lint docs-check
just test <image> [version]  # for every image you changed
just scan <image> [version]
```

The Build workflow runs the same checks, then builds every image version for linux/amd64 and
linux/arm64, plus the latest version of each on the portability bases (UBI 10, UBI 10 minimal
and Wolfi).

## Changing versions

[`versions.yml`](./versions.yml) is the single source. Change a version there, then run
`just lock docs` (and `just pin` for a new base). On a branch in this repository the Pins
workflow does this for you and re-runs Build. A pull request from a fork has to commit the
regenerated files itself.

Never hand-edit `versions.lock.json`, `images/locks/`, `releases.json` or `README.md`: edit
`versions.yml` or `HEADER.md`, and regenerate.

## Adding a tool or an image

- **A Go tool** is built from source: add it to `GO_BUILDS` in `scripts/images.py`, with the
  ldflags its own release uses, then list it under `tools` in `versions.yml`.
- **Any other download** needs an entry in `DOWNLOADS` in `scripts/images.py` and an install
  case in `images/common/fetch-tool.sh`.
- **An image** is a new `AS <name>` stage in `images/Containerfile`, an entry under `images`
  in `versions.yml`, and a smoke test suite in `tests/<name>.sh`.

In every case, `just lock` pins the new inputs and patches their known vulnerabilities, and the
README follows from `versions.yml`.

## Pull requests from forks

Builds pull Docker Hardened Images from `dhi.io`, which needs the repository's Docker Hub
credentials. GitHub does not pass secrets to workflows started from forks, so on a fork's pull
request the Build jobs cannot pull their bases. The Check and Portability jobs still run. A
maintainer builds your change from a branch in this repository before merging it.

## Conventions

- UK English, in code, comments, docs and commit messages.
- No en or em dashes anywhere; `just lint` checks.
- Shell: POSIX `sh` for anything under `images/` (it runs before bash exists on some bases),
  bash elsewhere. ShellCheck clean, formatted with shfmt.
- The Containerfile never calls a package manager or `useradd` directly; use the scripts in
  `images/common/`, so the base stays swappable.
- Fix scan findings at the source: raise the dependency, bump the tool or refresh the base.
  A finding that does not apply is set aside only with a VEX statement in
  `vex/libre-devops.openvex.json` giving the justification, never a blanket ignore.
- Workflows: `permissions: {}` at the top and the least each job needs, actions pinned by
  commit SHA, no persisted checkout credentials, and untrusted values passed through `env`,
  never interpolated into `run`. zizmor enforces most of this.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org).
- Never reuse, re-tag or delete an existing package or tag. New images get new names;
  `versions.yml` lists the protected ones.
