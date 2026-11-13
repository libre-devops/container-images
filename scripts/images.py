#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["pyyaml==6.0.3", "packaging==25.0"]
# ///
"""Turns versions.yml into everything the builds, tests and docs need.

Run it with uv, which installs the pinned dependencies on first use:

    uv run scripts/images.py <command> [arguments]

Commands:
    validate                         Check versions.yml, the lock and the base pins.
    matrix [--github-output]         CI matrices as JSON: builds, entries, portability.
    build-args IMAGE [VER] [--base]  Build arguments, one KEY=VALUE per line.
    test-env IMAGE [VER]             Smoke test environment, one KEY=VALUE per line.
    test-suites IMAGE [VERSION]      The smoke test scripts an image version runs, one per line.
    test-server-image                The image the CA trust test runs its TLS server in.
    labels IMAGE [VER]               OCI labels, one KEY=VALUE per line.
    tags IMAGE VER DATE              Tags for one release, as JSON.
    repos IMAGE                      The repository in each registry, one per line.
    local-ref IMAGE [VER] [--base]   The tag a local build gets.
    vex IMAGE [VER] [--base] -o F    Write the base image publisher's VEX, re-stated for our images.
    dockerhub                        Ensure every Docker Hub repository exists, is public, and has its overview.
    lock [--check]                   Pin every download, and patch known vulnerabilities.
    pin                              Re-resolve every base image tag to its digest.
    docs [--check]                   Write README.md from HEADER.md.
    record DIR                       Merge release records from DIR into releases.json.

What `lock` pins, in versions.lock.json:
    tools    The SHA-256 of every release download, per platform. Written once and
             never re-fetched, so an upstream asset that changes fails the build.
    go       For every Go tool built from source, each dependency with a known
             vulnerability (from OSV) and the fixed version the build raises it to.
             Recomputed on every run, so new advisories are picked up.
    python   Hash-locked requirements (images/locks/) for the Python tools, with any
             locked package that has a known vulnerability raised to a fixed version.
"""

from __future__ import annotations

import argparse
import base64
import functools
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

import yaml
from packaging.version import InvalidVersion, Version

ROOT = Path(__file__).resolve().parent.parent
VERSIONS = ROOT / "versions.yml"
LOCK = ROOT / "versions.lock.json"
RELEASES = ROOT / "releases.json"
HEADER = ROOT / "HEADER.md"
README = ROOT / "README.md"
CONTAINERFILE = "images/Containerfile"
PYTHON_LOCKS = "images/locks"

REPOSITORY = "https://github.com/libre-devops/container-images"
USER_AGENT = "libre-devops-container-images"
DIGEST = re.compile(r"@sha256:[0-9a-f]{64}$")
GENERATED = "<!-- Generated from HEADER.md and versions.yml by `just docs`. Edit those, not this file. -->\n"
OSV = "https://api.osv.dev/v1"

# Release downloads: GitHub repository, tag pattern, asset pattern, and the
# name each platform has in the asset. Platforms are amd64 and arm64 (glibc,
# or static builds that run anywhere), "<arch>-musl" where a tool ships a
# separate build for musl bases such as Alpine, and "any" for one asset for
# all. The Go toolchain comes from go.dev instead (see pin_go_toolchain).
DOWNLOADS: dict[str, tuple[str, str, str, dict[str, str]]] = {
    "shellcheck": ("koalaman/shellcheck", "v{v}", "shellcheck-v{v}.linux.{a}.tar.xz", {"amd64": "x86_64", "arm64": "aarch64"}),
    "jq": ("jqlang/jq", "jq-{v}", "jq-linux-{a}", {"amd64": "amd64", "arm64": "arm64"}),
    "uv": (
        "astral-sh/uv",
        "{v}",
        "uv-{a}.tar.gz",
        {
            "amd64": "x86_64-unknown-linux-gnu",
            "arm64": "aarch64-unknown-linux-gnu",
            "amd64-musl": "x86_64-unknown-linux-musl",
            "arm64-musl": "aarch64-unknown-linux-musl",
        },
    ),
    # Microsoft publishes no musl build of PowerShell for arm64.
    "powershell": (
        "PowerShell/PowerShell",
        "v{v}",
        "powershell-{v}-{a}.tar.gz",
        {"amd64": "linux-x64", "arm64": "linux-arm64", "amd64-musl": "linux-musl-x64"},
    ),
    "ldo-cli": ("libre-devops/ldo-cli", "v{v}", "libre_devops_helpers-{v}-py3-none-any.whl", {"any": ""}),
    # GitHub publishes no musl build of the runner.
    "github-runner": ("actions/runner", "v{v}", "actions-runner-linux-{a}-{v}.tar.gz", {"amd64": "x64", "arm64": "arm64"}),
    # CI only.
    "shfmt": ("mvdan/sh", "v{v}", "shfmt_v{v}_linux_{a}", {"amd64": "amd64", "arm64": "arm64"}),
    "trivy": ("aquasecurity/trivy", "v{v}", "trivy_{v}_Linux-{a}.tar.gz", {"amd64": "64bit", "arm64": "ARM64"}),
    "hadolint": ("hadolint/hadolint", "v{v}", "hadolint-linux-{a}", {"amd64": "x86_64", "arm64": "arm64"}),
    "cosign": ("sigstore/cosign", "v{v}", "cosign-linux-{a}", {"amd64": "amd64", "arm64": "arm64"}),
    "zizmor": ("zizmorcore/zizmor", "v{v}", "zizmor-{a}-unknown-linux-gnu.tar.gz", {"amd64": "x86_64", "arm64": "aarch64"}),
    "actionlint": ("rhysd/actionlint", "v{v}", "actionlint_{v}_linux_{a}.tar.gz", {"amd64": "amd64", "arm64": "arm64"}),
}
GO_ARCHES = ("amd64", "arm64")

# Downloads that are not GitHub release assets, and the platforms each pins.
# The Azure Pipelines agent is published on Microsoft's CDN, with its SHA-256
# in the GitHub release notes; a Galaxy collection is one tarball for all.
AZURE_PIPELINES_AGENT = {
    "amd64": "linux-x64",
    "arm64": "linux-arm64",
    "amd64-musl": "linux-musl-x64",
    "arm64-musl": "linux-musl-arm64",
}
GALAXY_COLLECTIONS = {"azure-azcollection": "azure.azcollection"}
# OpenSSH portable publishes signed tarballs, not checksums: a release is
# pinned only after its signature verifies against the OpenSSH release key
# (Damien Miller's), named here by fingerprint.
OPENSSH_CDN = "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH"
OPENSSH_RELEASE_KEY = "7168B983815A5EEF59A4ADFD2A3F414E736060BA"
# HashiCorp signs its releases' SHA256SUMS (Terraform providers in the
# hashicorp namespace, tfstacks) with this key. Microsoft signs azapi and
# msgraph with its registry partner key. A provider is pinned only once the
# checksums for its release verify against its namespace's key here.
HASHICORP_KEY = "C874011F0AB405110D02105534365D9472D7468F"
MICROSOFT_PROVIDER_KEY = "404BCB5E66712DE36720E0C36F0B91BDE98478CF"
PROVIDER_KEYS = {"hashicorp": HASHICORP_KEY, "azure": MICROSOFT_PROVIDER_KEY, "microsoft": MICROSOFT_PROVIDER_KEY}
TERRAFORM_REGISTRY = "https://registry.terraform.io"
PROVIDER_PLATFORMS = {"amd64": ("linux", "amd64"), "arm64": ("linux", "arm64")}
# A provider release joins the mirror once it is this many days old, as
# Renovate waits before taking a new tool.
PROVIDER_MIN_AGE_DAYS = 3
OTHER_DOWNLOADS: dict[str, tuple[str, ...]] = {
    "go": GO_ARCHES,
    "openssh": ("any",),
    "tfstacks": GO_ARCHES,
    "azure-pipelines-agent": tuple(AZURE_PIPELINES_AGENT),
    **{name: ("any",) for name in GALAXY_COLLECTIONS},
}


@dataclass(frozen=True)
class GoBuild:
    module: str
    tag: str
    binaries: dict[str, str]  # package path -> binary name
    ldflags: str = ""


# Go tools the images build from source rather than download, so that they
# carry a current toolchain and patched dependencies. ldflags follow each
# project's own release configuration.
GO_BUILDS: dict[str, GoBuild] = {
    "shfmt": GoBuild("mvdan.cc/sh/v3", "v{v}", {"./cmd/shfmt": "shfmt"}),
    "tenv": GoBuild(
        "github.com/tofuutils/tenv/v4", "v{v}", {"./cmd/tenv": "tenv", "./cmd/terraform": "terraform"}, "-X main.version=v{v}"
    ),
    "tflint": GoBuild("github.com/terraform-linters/tflint", "v{v}", {".": "tflint"}),
    "terraform-docs": GoBuild("github.com/terraform-docs/terraform-docs", "v{v}", {".": "terraform-docs"}),
    "conftest": GoBuild(
        "github.com/open-policy-agent/conftest",
        "v{v}",
        {".": "conftest"},
        "-X github.com/open-policy-agent/conftest/internal/version.Version={v}",
    ),
}

DISPLAY = {"shellcheck": "ShellCheck", "shfmt": "shfmt", "jq": "jq"}


class Failure(Exception):
    """A problem to report to the user, without a traceback."""


def note(message: str) -> None:
    print(message, file=sys.stderr)


def arg_name(name: str) -> str:
    return name.upper().replace("-", "_")


# Configuration ---------------------------------------------------------------


@dataclass(frozen=True)
class Entry:
    image: str
    version: str
    base_key: str
    base: str
    python: str | None
    latest: bool
    moving: tuple[str, ...]
    aliases: tuple[str, ...]
    flavour: str | None = None
    atop: str | None = None  # another image whose stage this one is built on
    contents: str | None = None  # this entry's README description, if not the image's

    @property
    def key(self) -> str:
        """What identifies the entry within its image: 1.17.1, or 1.17.1-alpine."""
        return f"{self.version}-{self.flavour}" if self.flavour else self.version

    @property
    def id(self) -> str:
        return f"{self.image}-{self.key}"

    @property
    def stem(self) -> str:
        """The front of the date tag: 3.12, 2.72.0-py3.12, or 1.17.1-alpine."""
        stem = f"{self.version}-py{self.python}" if self.python else self.version
        return f"{stem}-{self.flavour}" if self.flavour else stem

    def date_tag(self, date: str) -> str:
        return f"{self.stem}-{date}"

    def moving_tags(self) -> list[str]:
        tags = [self.version]
        parts = self.version.split(".")
        for kind in self.moving:
            if kind == "minor" and len(parts) > 2:
                tags.append(".".join(parts[:2]))
            elif kind == "major" and len(parts) > 1:
                tags.append(parts[0])
        tags.extend(self.aliases)
        if self.flavour:
            # Every tag of a flavour carries its suffix; its newest is the flavour itself.
            tags = [f"{t}-{self.flavour}" for t in tags] + ([self.flavour] if self.latest else [])
        elif self.latest:
            tags.append("latest")
        return list(dict.fromkeys(tags))


class Config:
    def __init__(self, data: dict):
        self.data = data
        self.registries: list[str] = data["registries"]
        self.platforms: dict[str, str] = data["platforms"]
        self.bases: dict[str, str] = data["bases"]
        self.portability: dict[str, str] = data.get("portability") or {}
        self.tools: dict[str, str] = {k: str(v) for k, v in data["tools"].items()}
        self.common: list[str] = data["common"]
        self.ci: list[str] = data.get("ci") or []
        self.images: dict[str, dict] = data["images"]
        self.terraform_providers: dict[str, list[str]] = {
            source: [str(v) for v in versions] for source, versions in (data.get("terraform_providers") or {}).items()
        }

    @classmethod
    def load(cls) -> Config:
        return cls(yaml.safe_load(VERSIONS.read_text()))

    def entries(self, image: str | None = None) -> list[Entry]:
        out = []
        for name, spec in self.images.items():
            if image and name != image:
                continue
            for item in spec["versions"]:
                key = item["base"]
                out.append(
                    Entry(
                        image=name,
                        version=item["version"],
                        base_key=key,
                        base=self.bases.get(key, ""),
                        python=item.get("python"),
                        latest=bool(item.get("latest")),
                        moving=tuple(item.get("moving") or ()),
                        aliases=tuple(item.get("aliases") or ()),
                        flavour=item.get("flavour"),
                        atop=item.get("atop"),
                        contents=item.get("contents"),
                    )
                )
        if image and not out:
            raise Failure(f"no image called '{image}' in versions.yml")
        return out

    def entry(self, image: str, version: str | None = None) -> Entry:
        """An image version by its key (1.17.1, or 1.17.1-alpine for a flavour);
        with no key, the latest version of the default flavour."""
        entries = self.entries(image)
        if not version:
            return next(e for e in entries if e.latest and not e.flavour)
        for e in entries:
            if e.key == version:
                return e
        known = ", ".join(e.key for e in entries)
        raise Failure(f"{image} has no version '{version}' (versions.yml has: {known})")

    def components(self, entry: Entry) -> list[Entry]:
        """The image versions an entry is made of: itself, the latest version of
        each image it `includes` (the toolbox), and, for an entry built `atop`
        another image, that image and everything it is made of."""
        out = {entry.id: entry}
        names = list(self.images[entry.image].get("includes") or [])
        names += [entry.atop] if entry.atop else []
        for name in names:
            for c in self.components(self.entry(name)):
                out.setdefault(c.id, c)
        return list(out.values())

    def python_minor(self, entry: Entry) -> str | None:
        if entry.image == "python":
            return entry.version
        if entry.python:
            return entry.python
        for c in self.components(entry):
            if c is not entry and (minor := self.python_minor(c)):
                return minor
        return None

    def tools_for(self, entry: Entry) -> list[str]:
        tools = list(self.common) + list(self.images[entry.image].get("tools") or [])
        for c in self.components(entry):
            tools += self.images[c.image].get("tools") or []
        return list(dict.fromkeys(tools))

    def os_packages(self, entry: Entry) -> list[str]:
        names = list(self.images[entry.image].get("os_packages") or [])
        for c in self.components(entry):
            names += self.images[c.image].get("os_packages") or []
        return list(dict.fromkeys(names))

    def downloads(self, entry: Entry) -> list[tuple[str, str]]:
        """(tool, version) for every release download an image version needs."""
        out = [("go", self.tools["go"])]
        out += [
            (t, self.tools[t])
            for t in self.tools_for(entry)
            if (t in DOWNLOADS or t in OTHER_DOWNLOADS) and t not in GO_BUILDS
        ]
        for c in self.components(entry):
            extra = self.images[c.image].get("download")
            if extra:
                out.append((extra, c.version))
        return list(dict.fromkeys(out))

    def go_builds(self, entry: Entry) -> list[tuple[str, str]]:
        return [(t, self.tools[t]) for t in self.tools_for(entry) if t in GO_BUILDS]

    def python_locks(self, entry: Entry) -> dict[str, dict]:
        """The hash-locked requirement sets an image version installs. Each
        includes pip-system-certs, so Python trusts the operating system's CA
        store (and any CA added to it) rather than a bundle of its own."""
        locks = {}
        for c in self.components(entry):
            if c.image == "azure-cli":
                locks["AZURE_CLI_LOCK"] = python_lock_spec(
                    "azure-cli", f"azure-cli=={c.version}\n{SYSTEM_CERTS}", c.version, c.python
                )
                ldo = self.tools["ldo-cli"]
                locks["LDO_CLI_LOCK"] = python_lock_spec(
                    "ldo-cli", f"libre-devops-helpers=={ldo}\n{SYSTEM_CERTS}", ldo, c.python, exclude="libre-devops-helpers"
                )
        if entry.image == "ansible":
            locks["ANSIBLE_LOCK"] = python_lock_spec("ansible", ansible_requirement(entry.version), entry.version, entry.python)
        elif entry.image == "ansible-azure":
            core = next(c for c in self.components(entry) if c.image == "ansible")
            collection = GALAXY_COLLECTIONS["azure-azcollection"]
            locks["ANSIBLE_LOCK"] = python_lock_spec(
                "ansible-azure",
                f"{ansible_requirement(core.version)}\n# and the requirements.txt of {collection}=={entry.version}",
                entry.version,
                self.python_minor(entry),
                collection=("azure-azcollection", entry.version),
            )
        return locks

    def providers(self, entry: Entry) -> dict[str, list[str]]:
        """The Terraform providers an image version carries in its mirror."""
        return self.terraform_providers if self.images[entry.image].get("provider_mirror") else {}

    def tests(self, entry: Entry) -> list[str]:
        suites = list(self.images[entry.image].get("tests") or [entry.image])
        for c in self.components(entry):
            if c is not entry:
                suites += self.tests(c)
        return list(dict.fromkeys(suites))

    def all_downloads(self) -> set[tuple[str, str]]:
        needed = {(t, self.tools[t]) for t in self.ci}
        for e in self.entries():
            needed.update(self.downloads(e))
        return needed

    def all_go_builds(self) -> set[tuple[str, str]]:
        return {b for e in self.entries() for b in self.go_builds(e)}

    def all_python_locks(self) -> dict[str, dict]:
        return {spec["key"]: spec for e in self.entries() for spec in self.python_locks(e).values()}

    def resolve_base(self, base: str | None, entry: Entry) -> str:
        if not base:
            return entry.base
        return self.bases.get(base) or self.portability.get(base) or base

    def repos(self, image: str) -> list[str]:
        return [f"{r}/{image}" for r in self.registries]


SYSTEM_CERTS = "pip-system-certs"


def ansible_requirement(core: str) -> str:
    """ansible-core with ansible-lint and the libraries common playbooks need:
    jmespath (json_query), netaddr (ipaddr filters) and pywinrm (Windows hosts).
    Unpinned names resolve to the newest release compatible with that core."""
    return "\n".join([f"ansible-core=={core}", "ansible-lint", "jmespath", "netaddr", "pywinrm", SYSTEM_CERTS])


def python_lock_spec(
    name: str, requirement: str, version: str, python: str, exclude: str = "", collection: tuple[str, str] | None = None
) -> dict:
    key = f"{name}-{version}-py{python}"
    return {
        "key": key,
        "requirement": requirement,
        "python": python,
        "file": f"{PYTHON_LOCKS}/{key}.txt",
        "exclude": exclude,
        "collection": collection,
    }


# HTTP helpers ------------------------------------------------------------------

# Answers that mean "try again shortly": rate limits and server-side failures.
RETRY_STATUSES = {429, 500, 502, 503, 504}


def urlopen(request: urllib.request.Request, timeout: int = 60, attempts: int = 4):
    """urllib.request.urlopen, retried with backoff when the connection drops,
    times out, or the server answers with a status in RETRY_STATUSES. Any other
    HTTP error is raised at once, for the caller to handle."""
    for attempt in range(1, attempts + 1):
        try:
            return urllib.request.urlopen(request, timeout=timeout)
        except urllib.error.HTTPError as error:
            if error.code not in RETRY_STATUSES or attempt == attempts:
                raise
            reason = f"HTTP {error.code}"
        except OSError as error:  # URLError, a reset connection, a timeout
            if attempt == attempts:
                raise
            reason = str(getattr(error, "reason", error))
        delay = 5 * 2 ** (attempt - 1)
        where = urllib.parse.urlsplit(request.full_url)
        print(f"{where.netloc}{where.path}: {reason}, retrying in {delay}s", file=sys.stderr)
        time.sleep(delay)
    raise AssertionError("unreachable")


def http(url: str, data: dict | None = None, headers: dict[str, str] | None = None, timeout: int = 60):
    body = json.dumps(data).encode() if data is not None else None
    request = urllib.request.Request(url, data=body, headers={"User-Agent": USER_AGENT, **(headers or {})})
    if body is not None:
        request.add_header("Content-Type", "application/json")
    return urlopen(request, timeout=timeout)


def http_json(url: str, data: dict | None = None, headers: dict[str, str] | None = None):
    with http(url, data, headers) as response:
        return json.load(response)


def github_token() -> str | None:
    for var in ("GITHUB_TOKEN", "GH_TOKEN"):
        if os.environ.get(var):
            return os.environ[var]
    if shutil.which("gh"):
        result = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    return None


def sha256_of_url(url: str) -> str:
    digest = hashlib.sha256()
    with http(url, timeout=300) as response:
        for chunk in iter(lambda: response.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


# Release downloads ---------------------------------------------------------------


def load_lock() -> dict:
    lock = json.loads(LOCK.read_text()) if LOCK.exists() else {}
    for section in ("tools", "go", "python", "providers"):
        lock.setdefault(section, {})
    return lock


def asset_spec(lock: dict, tool: str, version: str) -> str:
    try:
        assets = lock["tools"][tool][version]
    except KeyError:
        raise Failure(f"{tool} {version} is not pinned in versions.lock.json; run `just lock`") from None
    return " ".join(f"{arch}|{a['url']}|{a['sha256']}" for arch, a in sorted(assets.items()))


def pin_go_toolchain(version: str) -> dict:
    releases = http_json("https://go.dev/dl/?mode=json&include=all")
    files = next((r["files"] for r in releases if r["version"] == f"go{version}"), None)
    if not files:
        raise Failure(f"go.dev has no Go {version}")
    pinned = {}
    for arch in GO_ARCHES:
        f = next((f for f in files if f["os"] == "linux" and f["arch"] == arch and f["kind"] == "archive"), None)
        if not f:
            raise Failure(f"go.dev has no linux/{arch} archive of Go {version}")
        pinned[arch] = {"url": f"https://go.dev/dl/{f['filename']}", "sha256": f["sha256"]}
        note(f"  go {version} {arch}: {f['sha256']}")
    return pinned


def pin_azure_pipelines_agent(version: str, token: str | None) -> dict:
    """The agent's tarballs, with the SHA-256 Microsoft lists for each in the
    release notes of the matching GitHub release."""
    headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = http_json(f"https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/tags/v{version}", headers=headers)["body"]
    pinned = {}
    for arch, name in AZURE_PIPELINES_AGENT.items():
        asset = f"vsts-agent-{name}-{version}.tar.gz"
        row = re.search(rf"\[{re.escape(asset)}\]\((https://[^)\s]+)\)\s*\|\s*([0-9a-f]{{64}})", body)
        if not row:
            raise Failure(f"the release notes of azure-pipelines-agent v{version} list no SHA-256 for {asset}")
        pinned[arch] = {"url": row[1], "sha256": row[2]}
        note(f"  azure-pipelines-agent {version} {arch}: {row[2]}")
    return pinned


def pin_galaxy_collection(tool: str, version: str) -> dict:
    namespace, name = GALAXY_COLLECTIONS[tool].split(".")
    meta = http_json(
        f"https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/{namespace}/{name}/versions/{version}/"
    )
    note(f"  {tool} {version}: {meta['artifact']['sha256']}")
    return {"any": {"url": meta["download_url"], "sha256": meta["artifact"]["sha256"]}}


def fetch_bytes(url: str) -> bytes:
    with http(url, timeout=300) as response:
        return response.read()


def gpg_verified(data: bytes, signature: bytes, keys: bytes, fingerprint: str) -> bool:
    """Whether a detached signature over data verifies, made by the key with
    this primary fingerprint (from among the armoured keys given)."""
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        home = work / "gnupg"
        home.mkdir(mode=0o700)
        (work / "keys.asc").write_bytes(keys)
        (work / "data").write_bytes(data)
        (work / "data.sig").write_bytes(signature)
        env = {**os.environ, "GNUPGHOME": str(home)}
        subprocess.run(["gpg", "--batch", "--quiet", "--import", str(work / "keys.asc")], env=env, check=True, capture_output=True)
        result = subprocess.run(
            ["gpg", "--batch", "--status-fd", "1", "--verify", str(work / "data.sig"), str(work / "data")],
            env=env, capture_output=True, text=True,
        )  # fmt: skip
    return bool(re.search(rf"^\[GNUPG:\] VALIDSIG .* {fingerprint}$", result.stdout, flags=re.M))


def pin_openssh(version: str) -> dict:
    """The OpenSSH portable release tarball, pinned by SHA-256 once its PGP
    signature verifies against OPENSSH_RELEASE_KEY."""
    url = f"{OPENSSH_CDN}/portable/openssh-{version}.tar.gz"
    tarball = fetch_bytes(url)
    if not gpg_verified(tarball, fetch_bytes(f"{url}.asc"), fetch_bytes(f"{OPENSSH_CDN}/RELEASE_KEY.asc"), OPENSSH_RELEASE_KEY):
        raise Failure(f"openssh-{version}.tar.gz is not signed by the OpenSSH release key {OPENSSH_RELEASE_KEY}")
    digest = hashlib.sha256(tarball).hexdigest()
    note(f"  openssh {version}: signature verified, {digest}")
    return {"any": {"url": url, "sha256": digest}}


def sums_entry(sums: bytes, filename: str) -> str:
    for line in sums.decode().splitlines():
        digest, _, name = line.partition("  ")
        if name.strip() == filename:
            return digest
    raise Failure(f"no checksum for {filename}")


def pin_tfstacks(version: str) -> dict:
    """tfstacks from releases.hashicorp.com, once its SHA256SUMS verify against
    HashiCorp's key."""
    base = f"https://releases.hashicorp.com/tfstacks/{version}"
    sums = fetch_bytes(f"{base}/tfstacks_{version}_SHA256SUMS")
    key = fetch_bytes("https://www.hashicorp.com/.well-known/pgp-key.txt")
    if not gpg_verified(sums, fetch_bytes(f"{base}/tfstacks_{version}_SHA256SUMS.sig"), key, HASHICORP_KEY):
        raise Failure(f"the checksums of tfstacks {version} are not signed by HashiCorp's key {HASHICORP_KEY}")
    pinned = {}
    for arch in GO_ARCHES:
        filename = f"tfstacks_{version}_linux_{arch}.zip"
        pinned[arch] = {"url": f"{base}/{filename}", "sha256": sums_entry(sums, filename)}
        note(f"  tfstacks {version} {arch}: {pinned[arch]['sha256']}")
    return pinned


def pin_provider(source: str, version: str) -> dict:
    """A Terraform provider release for each platform, from the registry, once
    its SHA256SUMS verify against the key PROVIDER_KEYS names for its namespace."""
    namespace = source.split("/")[0]
    fingerprint = PROVIDER_KEYS.get(namespace)
    if not fingerprint:
        raise Failure(f"no signing key is pinned for the {namespace} namespace (PROVIDER_KEYS)")
    pinned: dict[str, dict] = {}
    verified: dict[str, bytes] = {}
    for arch, (os_name, cpu) in PROVIDER_PLATFORMS.items():
        meta = http_json(f"{TERRAFORM_REGISTRY}/v1/providers/{source}/{version}/download/{os_name}/{cpu}")
        if meta["shasums_url"] not in verified:
            sums = fetch_bytes(meta["shasums_url"])
            keys = "\n".join(k["ascii_armor"] for k in meta["signing_keys"]["gpg_public_keys"]).encode()
            if not gpg_verified(sums, fetch_bytes(meta["shasums_signature_url"]), keys, fingerprint):
                raise Failure(f"the checksums of {source} {version} are not signed by key {fingerprint}")
            verified[meta["shasums_url"]] = sums
        digest = sums_entry(verified[meta["shasums_url"]], meta["filename"])
        if digest != meta["shasum"]:
            raise Failure(f"{source} {version} {arch}: the registry's checksum differs from the signed one")
        pinned[arch] = {"url": meta["download_url"], "sha256": digest}
        note(f"  {source} {version} {arch}: {digest}")
    return pinned


def newest_provider_minors(source: str, count: int) -> list[str]:
    """The newest patch of each of the newest `count` minor releases of a
    provider, among stable releases for every platform that are at least
    PROVIDER_MIN_AGE_DAYS old."""
    import datetime

    listing = http_json(f"{TERRAFORM_REGISTRY}/v1/providers/{source}/versions")["versions"]
    wanted = {f"{os_name}/{cpu}" for os_name, cpu in PROVIDER_PLATFORMS.values()}
    candidates = sorted(
        (
            Version(v["version"])
            for v in listing
            if re.fullmatch(r"\d+\.\d+\.\d+", v["version"])
            and wanted <= {f"{p['os']}/{p['arch']}" for p in v.get("platforms", [])}
        ),
        reverse=True,
    )
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=PROVIDER_MIN_AGE_DAYS)
    chosen: dict[tuple[int, int], Version] = {}
    for v in candidates:
        if len(chosen) == count:
            break
        if (v.major, v.minor) in chosen:
            continue
        published = http_json(f"{TERRAFORM_REGISTRY}/v1/providers/{source}/{v}")["published_at"]
        if datetime.datetime.fromisoformat(published.replace("Z", "+00:00")) > cutoff:
            continue
        chosen[(v.major, v.minor)] = v
    return [str(v) for v in chosen.values()]


def pin_download(tool: str, version: str, token: str | None) -> dict:
    if tool == "go":
        return pin_go_toolchain(version)
    if tool == "openssh":
        return pin_openssh(version)
    if tool == "tfstacks":
        return pin_tfstacks(version)
    if tool == "azure-pipelines-agent":
        return pin_azure_pipelines_agent(version, token)
    if tool in GALAXY_COLLECTIONS:
        return pin_galaxy_collection(tool, version)
    repo, tag_pattern, asset_pattern, arches = DOWNLOADS[tool]
    tag = tag_pattern.format(v=version)
    headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        release = http_json(f"https://api.github.com/repos/{repo}/releases/tags/{tag}", headers=headers)
    except urllib.error.HTTPError as error:
        raise Failure(f"cannot read release {tag} of {repo}: HTTP {error.code}") from None
    assets = {a["name"]: a for a in release.get("assets", [])}
    pinned = {}
    for arch, name in arches.items():
        asset_name = asset_pattern.format(v=version, a=name)
        asset = assets.get(asset_name)
        if not asset:
            raise Failure(f"{repo} {tag} has no asset {asset_name}")
        url = asset["browser_download_url"]
        digest = (asset.get("digest") or "").removeprefix("sha256:")
        if not re.fullmatch(r"[0-9a-f]{64}", digest):
            note(f"  {asset_name}: GitHub records no digest; hashing the download")
            digest = sha256_of_url(url)
        pinned[arch] = {"url": url, "sha256": digest}
        note(f"  {tool} {version} {arch}: {digest}")
    return pinned


# OSV: known vulnerabilities and their fixed versions -----------------------------


def semver_key(version: str) -> tuple:
    v = version.removeprefix("v").split("+", 1)[0]
    core, _, pre = v.partition("-")
    numbers = [int(p) if p.isdigit() else 0 for p in core.split(".")]
    numbers += [0] * (3 - len(numbers))
    if not pre:
        return (*numbers[:3], 1, ())
    ids = tuple((0, int(p), "") if p.isdigit() else (1, 0, p) for p in pre.split("."))
    return (*numbers[:3], 0, ids)


def pypi_key(version: str):
    try:
        return Version(version)
    except InvalidVersion:
        return Version("0")


@functools.cache
def osv_vuln(vuln_id: str) -> dict:
    return http_json(f"{OSV}/vulns/{vuln_id}")


def osv_fixes(ecosystem: str, packages: list[tuple[str, str]]) -> tuple[dict[str, str], list[str]]:
    """For each (name, version), the lowest version that fixes every known
    vulnerability affecting it, and a list of the ones with no fix yet."""
    if not packages:
        return {}, []
    key = semver_key if ecosystem == "Go" else pypi_key
    normalise = (lambda n: n) if ecosystem == "Go" else (lambda n: re.sub(r"[-_.]+", "-", n).lower())
    queries = [{"package": {"name": n, "ecosystem": ecosystem}, "version": v} for n, v in packages]
    results = []
    for start in range(0, len(queries), 500):
        results += http_json(f"{OSV}/querybatch", {"queries": queries[start : start + 500]})["results"]
    fixes: dict[str, str] = {}
    unfixed: list[str] = []
    for (name, version), result in zip(packages, results):
        current = key(version)
        for summary in result.get("vulns") or []:
            vuln = osv_vuln(summary["id"])
            if vuln.get("withdrawn"):
                continue
            fix, affected = None, False
            for aff in vuln.get("affected", []):
                pkg = aff.get("package", {})
                if pkg.get("ecosystem") != ecosystem or normalise(pkg.get("name", "")) != normalise(name):
                    continue
                for rng in aff.get("ranges", []):
                    if rng.get("type") not in ("SEMVER", "ECOSYSTEM"):
                        continue
                    introduced = None
                    for event in rng.get("events", []):
                        if "introduced" in event:
                            introduced = event["introduced"]
                        elif introduced is not None and ("fixed" in event or "last_affected" in event):
                            upper = event.get("fixed") or event["last_affected"]
                            inside = key(introduced) <= current and (
                                current < key(upper) if "fixed" in event else current <= key(upper)
                            )
                            if inside:
                                affected = True
                                if "fixed" in event and (fix is None or key(upper) < key(fix)):
                                    fix = upper
                            introduced = None
                    if introduced is not None and key(introduced) <= current:
                        affected = True
            if not affected:
                continue
            if fix is None:
                unfixed.append(f"{name} {version}: {summary['id']} (no fix released)")
            elif name not in fixes or key(fix) > key(fixes[name]):
                fixes[name] = fix
    return fixes, unfixed


# Go tools: patched dependencies -------------------------------------------------


def module_escape(path: str) -> str:
    return re.sub(r"[A-Z]", lambda m: "!" + m.group(0).lower(), path)


def go_requirements(go_mod: str) -> tuple[dict[str, str], str]:
    requires: dict[str, str] = {}
    go_version = ""
    block = False
    for raw in go_mod.splitlines():
        line = raw.split("//", 1)[0].strip()
        if line.startswith("go "):
            go_version = line.split()[1]
        if line.startswith("require ("):
            block = True
            continue
        if block and line == ")":
            block = False
            continue
        parts = line.split()
        if block and len(parts) >= 2:
            requires[parts[0]] = parts[1]
        elif parts[:1] == ["require"] and len(parts) >= 3:
            requires[parts[1]] = parts[2]
    return requires, go_version


PSEUDO_VERSION = re.compile(r"-(?:0\.)?\d{14}-[0-9a-f]{12}$")


def tagged_release_at_least(module: str, fixed: str) -> str:
    """OSV sometimes gives a fix as a pseudo-version (the fixing commit). Prefer
    the first tagged release at or after it, when the module has one."""
    if not PSEUDO_VERSION.search(fixed):
        return fixed
    with http(f"https://proxy.golang.org/{module_escape(module)}/@v/list") as response:
        tags = [t for t in response.read().decode().split() if not PSEUDO_VERSION.search(t) and "-" not in t]
    later = sorted((t for t in tags if semver_key(t) >= semver_key(fixed)), key=semver_key)
    return later[0] if later else fixed


def lock_go_build(tool: str, version: str, go_toolchain: str) -> dict:
    build = GO_BUILDS[tool]
    tag = build.tag.format(v=version)
    with http(f"https://proxy.golang.org/{module_escape(build.module)}/@v/{tag}.mod") as response:
        requires, needs_go = go_requirements(response.read().decode())
    if needs_go and semver_key(needs_go) > semver_key(go_toolchain):
        raise Failure(f"{tool} {version} needs Go {needs_go}, newer than the pinned Go {go_toolchain}")
    # A fixed version can itself be affected by another advisory (one that
    # never touched the original version), so re-audit the raised versions
    # until none of them is affected.
    overrides: dict[str, str] = {}
    unfixed: list[str] = []
    for _ in range(6):
        current = {**requires, **overrides}
        fixes, unfixed = osv_fixes("Go", sorted(current.items()))
        raised = {
            m: tagged_release_at_least(m, v if v.startswith("v") else f"v{v}")
            for m, v in fixes.items()
            if semver_key(v) > semver_key(current[m])
        }
        if not raised:
            break
        overrides.update(raised)
    else:
        raise Failure(f"{tool} {version}: dependencies remain vulnerable after six rounds of patching")
    overrides = dict(sorted(overrides.items()))
    for module, fixed in overrides.items():
        note(f"  {tool} {version}: {module} {requires[module]} -> {fixed}")
    for line in unfixed:
        note(f"  {tool} {version}: warning: {line}")
    return {"module": build.module, "overrides": overrides}


def go_spec(lock: dict, tool: str, version: str) -> str:
    build = GO_BUILDS[tool]
    try:
        entry = lock["go"][tool][version]
    except KeyError:
        raise Failure(f"{tool} {version} has no Go build pin in versions.lock.json; run `just lock`") from None
    packages = ",".join(f"{pkg}:{binary}" for pkg, binary in build.binaries.items())
    overrides = " ".join(f"{m}@{v}" for m, v in entry["overrides"].items())
    return ";".join([build.module, build.tag.format(v=version), packages, build.ldflags.format(v=version), overrides])


# Python tools: hash-locked, patched requirements ------------------------------


def locked_packages(text: str) -> list[tuple[str, str]]:
    found = re.findall(r"^([A-Za-z0-9][A-Za-z0-9._-]*)==([^\s;\\]+)", text, flags=re.M)
    return sorted(set(found))


def strip_requirement(text: str, name: str) -> str:
    out, skipping = [], False
    for line in text.splitlines(keepends=True):
        if re.match(rf"^{re.escape(name)}==", line):
            skipping = True
            continue
        if skipping and line[:1] in (" ", "\t"):
            continue
        skipping = False
        out.append(line)
    return "".join(out)


def overrides_file(spec: dict) -> str:
    """The committed file of security raises for one lock, next to it. Its path
    is recorded in the lock's annotations, so it must be stable: a temporary
    path would change the lock on every run."""
    return spec["file"].removesuffix(".txt") + ".overrides.txt"


def compile_python_lock(spec: dict, overrides: dict[str, str], upgrade: list[str]) -> str:
    path = ROOT / spec["file"]
    path.parent.mkdir(parents=True, exist_ok=True)
    command = [
        "uv", "pip", "compile", "-", "--quiet", "--universal", "--generate-hashes",
        "--python-version", spec["python"], "--custom-compile-command", "just lock",
        "--output-file", spec["file"],
    ]  # fmt: skip
    raises = ROOT / overrides_file(spec)
    if overrides:
        raises.write_text(
            "# Generated by `just lock`: packages raised to fix known vulnerabilities (from OSV).\n"
            + "".join(f"{name}{spec_text}\n" for name, spec_text in sorted(overrides.items()))
        )
        command += ["--override", overrides_file(spec)]
    elif raises.exists():
        raises.unlink()
    for name in upgrade:
        command += ["--upgrade-package", name]
    requirement = spec["requirement"] + "\n"
    if spec.get("collection"):
        requirement += collection_requirements(*spec["collection"], spec["collection_asset"])
    result = subprocess.run(command, input=requirement, text=True, capture_output=True, cwd=ROOT)
    if result.returncode != 0:
        raise Failure(f"uv could not lock {spec['requirement']} for Python {spec['python']}:\n{result.stderr}")
    text = path.read_text()
    if spec["exclude"]:
        text = strip_requirement(text, spec["exclude"])
        path.write_text(text)
    return text


def collection_requirements(tool: str, version: str, asset: dict) -> str:
    """The requirements.txt inside a pinned Galaxy collection tarball."""
    import io
    import tarfile

    with http(asset["url"], timeout=300) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != asset["sha256"]:
        raise Failure(f"{tool} {version} does not match its pinned SHA-256")
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        member = tar.extractfile("requirements.txt")
        if member is None:
            raise Failure(f"{tool} {version} has no requirements.txt")
        return member.read().decode()


def lock_python(spec: dict, previous: dict | None) -> dict:
    same_inputs = previous and previous.get("requirement") == spec["requirement"] and previous.get("python") == spec["python"]
    overrides: dict[str, str] = dict(previous["overrides"]) if same_inputs else {}
    if not same_inputs and (ROOT / spec["file"]).exists():
        (ROOT / spec["file"]).unlink()
    upgrade: list[str] = []
    for _ in range(4):
        text = compile_python_lock(spec, overrides, upgrade)
        fixes, unfixed = osv_fixes("PyPI", locked_packages(text))
        new = {}
        for name, fixed in fixes.items():
            major = pypi_key(fixed).major
            new[name] = f">={fixed},<{major + 1}" if major >= 1 else f">={fixed}"
        new = {n: s for n, s in new.items() if overrides.get(n) != s}
        if not new:
            for line in unfixed:
                note(f"  {spec['key']}: warning: {line}")
            break
        for name, s in new.items():
            note(f"  {spec['key']}: raising {name} to {s} (known vulnerability)")
        overrides.update(new)
        upgrade = list(new)
    else:
        raise Failure(f"{spec['key']}: vulnerable packages remain after four rounds of patching")
    return {k: spec[k] for k in ("requirement", "python", "file")} | {"overrides": dict(sorted(overrides.items()))}


def cmd_lock(cfg: Config, check: bool) -> None:
    lock = load_lock()
    needed = cfg.all_downloads()
    go_needed = cfg.all_go_builds()
    py_needed = cfg.all_python_locks()
    providers_needed = {(src, v) for e in cfg.entries() for src, versions in cfg.providers(e).items() for v in versions}

    def pinned(tool: str, version: str) -> bool:
        arches = set(OTHER_DOWNLOADS[tool]) if tool in OTHER_DOWNLOADS else set(DOWNLOADS[tool][3])
        return set(lock["tools"].get(tool, {}).get(version, {})) == arches

    if check:
        problems = [f"download not pinned: {t} {v}" for t, v in sorted(needed) if not pinned(t, v)]
        problems += [f"Go build not locked: {t} {v}" for t, v in sorted(go_needed) if v not in lock["go"].get(t, {})]
        for key, spec in sorted(py_needed.items()):
            entry = lock["python"].get(key)
            if not entry or entry["requirement"] != spec["requirement"] or not (ROOT / spec["file"]).exists():
                problems.append(f"Python lock missing or stale: {key}")
        stale = [f"{t} {v}" for t, vs in lock["tools"].items() for v in vs if (t, v) not in needed]
        stale += [f"Go build {t} {v}" for t, vs in lock["go"].items() for v in vs if (t, v) not in go_needed]
        stale += [f"Python lock {k}" for k in lock["python"] if k not in py_needed]
        problems += [
            f"provider not pinned: {src} {v}"
            for src, v in sorted(providers_needed)
            if set(lock["providers"].get(src, {}).get(v, {})) != set(PROVIDER_PLATFORMS)
        ]
        stale += [f"provider {src} {v}" for src, vs in lock["providers"].items() for v in vs if (src, v) not in providers_needed]
        problems += [f"no longer used: {s}" for s in stale]
        if problems:
            raise Failure(
                "versions.lock.json is out of date; run `just lock` (on a branch in this repository, "
                "the Pins workflow does it for you and re-runs this check):\n  " + "\n  ".join(problems)
            )
        return

    token = github_token()
    tools: dict[str, dict] = {}
    for tool, version in sorted(needed):
        existing = lock["tools"].get(tool, {}).get(version) or {}
        if not pinned(tool, version):
            note(f"pinning {tool} {version}")
            fresh = pin_download(tool, version, token)
            # A platform pinned before must still match: if upstream replaced
            # the asset since, fail rather than quietly trust the new one.
            for arch, old in existing.items():
                if arch in fresh and fresh[arch]["sha256"] != old["sha256"]:
                    raise Failure(
                        f"{tool} {version} {arch} changed upstream since it was pinned: "
                        f"{old['sha256']} is now {fresh[arch]['sha256']}"
                    )
            existing = {**fresh, **existing}
        tools.setdefault(tool, {})[version] = existing

    providers: dict[str, dict] = {}
    for src, version in sorted(providers_needed):
        existing = lock["providers"].get(src, {}).get(version) or {}
        if set(existing) != set(PROVIDER_PLATFORMS):
            note(f"pinning {src} {version}")
            fresh = pin_provider(src, version)
            for arch, old in existing.items():
                if arch in fresh and fresh[arch]["sha256"] != old["sha256"]:
                    raise Failure(f"{src} {version} {arch} changed upstream since it was pinned")
            existing = {**fresh, **existing}
        providers.setdefault(src, {})[version] = existing

    go_version = cfg.tools["go"]
    toolchain_fixes, _ = osv_fixes("Go", [("stdlib", go_version)])
    if toolchain_fixes:
        note(f"warning: Go {go_version} has known vulnerabilities fixed in {toolchain_fixes['stdlib']}; bump `go`")
    go: dict[str, dict] = {}
    for tool, version in sorted(go_needed):
        note(f"auditing Go build {tool} {version}")
        go.setdefault(tool, {})[version] = lock_go_build(tool, version, go_version)

    python: dict[str, dict] = {}
    for key, spec in sorted(py_needed.items()):
        note(f"locking {key}")
        if spec.get("collection"):
            tool, version = spec["collection"]
            spec["collection_asset"] = tools[tool][version]["any"]
        python[key] = lock_python(spec, lock["python"].get(key))
    for key, entry in lock["python"].items():
        if key not in python:
            for stale in (entry["file"], overrides_file(entry)):
                if (ROOT / stale).exists():
                    (ROOT / stale).unlink()

    LOCK.write_text(
        json.dumps(
            {
                "_comment": "Generated by `just lock` from versions.yml. Do not edit by hand.",
                "tools": tools,
                "go": go,
                "python": python,
                "providers": providers,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )


# Registry ----------------------------------------------------------------------


ACCEPT = ", ".join(
    [
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.docker.distribution.manifest.list.v2+json",
        "application/vnd.oci.image.manifest.v1+json",
        "application/vnd.docker.distribution.manifest.v2+json",
    ]
)


def parse_ref(ref: str) -> tuple[str, str, str]:
    name = ref.split("@", 1)[0]
    host, _, rest = name.partition("/")
    if "." not in host and ":" not in host:
        raise Failure(f"'{ref}' must name its registry, for example docker.io/library/debian:13-slim")
    repo, _, tag = rest.rpartition(":")
    if not repo or "/" in tag:
        raise Failure(f"'{ref}' must have an explicit tag")
    if host == "docker.io" and "/" not in repo:
        repo = f"library/{repo}"
    return host, repo, tag


def registry_credentials(host: str) -> tuple[str, str] | None:
    hub = host in ("docker.io", "dhi.io")
    if hub and os.environ.get("DOCKERHUB_USERNAME") and os.environ.get("DOCKERHUB_TOKEN"):
        return os.environ["DOCKERHUB_USERNAME"], os.environ["DOCKERHUB_TOKEN"]
    files = [
        os.environ.get("REGISTRY_AUTH_FILE"),
        f"{os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')}/containers/auth.json",
        str(Path.home() / ".config/containers/auth.json"),
        str(Path.home() / ".docker/config.json"),
    ]
    # Docker Hardened Images use the Docker Hub account, so a docker.io login will do.
    keys = [host, f"https://{host}"] + (["docker.io", "https://index.docker.io/v1/"] if hub else [])
    for path in filter(None, files):
        try:
            auths = json.loads(Path(path).read_text()).get("auths", {})
        except (OSError, ValueError):
            continue
        for key in keys:
            encoded = (auths.get(key) or {}).get("auth")
            if encoded:
                user, _, password = base64.b64decode(encoded).decode().partition(":")
                return user, password
    return None


def registry_get(host: str, repo: str, path: str, accept: str) -> bytes:
    api = "registry-1.docker.io" if host == "docker.io" else host
    url = f"https://{api}/v2/{repo}/{path}"
    request = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": USER_AGENT})
    try:
        with urlopen(request) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        if error.code != 401:
            raise Failure(f"{host}/{repo}: HTTP {error.code} for {path}") from None
        challenge = error.headers.get("WWW-Authenticate", "")
    params = dict(re.findall(r'(\w+)="([^"]*)"', challenge))
    if "realm" not in params:
        raise Failure(f"{host} asked for authentication without a usable challenge")
    query = urllib.parse.urlencode({"service": params.get("service", ""), "scope": f"repository:{repo}:pull"})
    token_request = urllib.request.Request(f"{params['realm']}?{query}", headers={"User-Agent": USER_AGENT})
    credentials = registry_credentials(host)
    if credentials:
        basic = base64.b64encode(":".join(credentials).encode()).decode()
        token_request.add_header("Authorization", f"Basic {basic}")
    try:
        with urlopen(token_request) as response:
            token_body = json.load(response)
    except urllib.error.HTTPError as error:
        hint = "" if credentials else " (no credentials found: log in with podman or docker, or set DOCKERHUB_USERNAME and DOCKERHUB_TOKEN)"
        raise Failure(f"{host}: cannot get a pull token, HTTP {error.code}{hint}") from None
    token = token_body.get("token") or token_body.get("access_token")
    request.add_header("Authorization", f"Bearer {token}")
    try:
        with urlopen(request) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        raise Failure(f"{host}/{repo}: HTTP {error.code} for {path}") from None


def resolve_digest(ref: str) -> tuple[str, set[str]]:
    """The digest a tag points at now, and the platforms its index offers."""
    host, repo, tag = parse_ref(ref)
    body = registry_get(host, repo, f"manifests/{tag}", ACCEPT)
    digest = "sha256:" + hashlib.sha256(body).hexdigest()
    manifest = json.loads(body)
    platforms = {
        f"{m['platform']['os']}/{m['platform']['architecture']}"
        for m in manifest.get("manifests", [])
        if m.get("platform", {}).get("os") not in (None, "unknown")
    }
    return digest, platforms


def cmd_pin(cfg: Config) -> None:
    """Re-resolve every tag under bases and portability to its digest, and the
    versions of every provider under terraform_providers, editing versions.yml
    in place so its comments survive."""
    lines = VERSIONS.read_text().splitlines(keepends=True)
    section = None
    published = {e.base_key for e in cfg.entries()}
    for i, line in enumerate(lines):
        top = re.match(r"^([A-Za-z][\w-]*):", line)
        if top:
            section = top.group(1)
            continue
        if section == "terraform_providers":
            match = re.match(r"^(\s+)([\w.-]+/[\w.-]+):\s*\[(.*)\]\s*$", line)
            if match:
                indent, source, current = match.groups()
                count = len([v for v in current.split(",") if v.strip()]) or 3
                versions = newest_provider_minors(source, count)
                new = ", ".join(f'"{v}"' for v in versions)
                note(f"{source}: {', '.join(versions)} ({'unchanged' if new == current.strip() else 'updated'})")
                lines[i] = f"{indent}{source}: [{new}]\n"
            continue
        if section not in ("bases", "portability"):
            continue
        match = re.match(r"^(\s+)([\w.-]+):\s*(\S+)\s*$", line)
        if not match:
            continue
        indent, key, ref = match.groups()
        name = ref.split("@", 1)[0]
        digest, platforms = resolve_digest(name)
        need = set(cfg.platforms) if (section == "bases" and key in published) else {"linux/amd64"}
        if not need <= platforms:
            raise Failure(f"{name} does not offer {', '.join(sorted(need - platforms))}")
        new = f"{name}@{digest}"
        note(f"{key}: {new} ({'unchanged' if new == ref else 'updated'})")
        lines[i] = f"{indent}{key}: {new}\n"
    VERSIONS.write_text("".join(lines))


# Vendor VEX --------------------------------------------------------------------


def purl_forms(purl: str) -> set[str]:
    """A package URL as the vendor wrote it, plus the form Trivy matches: for
    Debian and RPM packages Trivy carries the epoch as a qualifier
    (pkg:deb/debian/zlib1g@1.3?epoch=1), not in the version (@1%3A1.3)."""
    forms = {purl}
    match = re.match(r"^(pkg:(?:deb|rpm)/[^@]+)@(\d+)(?:%3A|:)(.+)$", purl)
    if match:
        forms.add(f"{match.group(1)}@{match.group(3)}?epoch={match.group(2)}")
    return forms


def vendor_vex(ref: str) -> list[dict]:
    """The OpenVEX statements a base image's publisher attached to the pinned
    digest (Docker Hardened Images attach signed ones, saying for example that a
    patched package is not affected by a CVE that scanners still match).

    They are written against the vendor's image, so they would not apply to an
    image built on it; this re-states each `not_affected` or `fixed` statement
    against the package URLs themselves, so Trivy applies it to ours. A base
    with no VEX attached yields nothing."""
    name, _, digest = ref.partition("@")
    if not digest:
        return []
    host, repo, _ = parse_ref(name)
    try:
        index = json.loads(registry_get(host, repo, f"manifests/{digest}", ACCEPT))
    except Failure:
        return []
    subjects = [m["digest"] for m in index.get("manifests", []) if m.get("platform", {}).get("os") == "linux"]
    statements: dict[str, dict] = {}
    for subject in subjects or [digest]:
        try:
            referrers = json.loads(
                registry_get(host, repo, f"referrers/{subject}", "application/vnd.oci.image.index.v1+json")
            )
        except Failure:
            continue
        for referrer in referrers.get("manifests", []):
            predicate = (referrer.get("annotations") or {}).get("in-toto.io/predicate-type", "")
            if not predicate.startswith("https://openvex.dev/"):
                continue
            manifest = json.loads(
                registry_get(host, repo, f"manifests/{referrer['digest']}", "application/vnd.oci.image.manifest.v1+json")
            )
            for layer in manifest.get("layers", []):
                body = json.loads(registry_get(host, repo, f"blobs/{layer['digest']}", "*/*"))
                if "payload" in body:  # a DSSE envelope
                    body = json.loads(base64.b64decode(body["payload"]))
                for statement in body.get("predicate", body).get("statements", []):
                    if statement.get("status") not in ("not_affected", "fixed"):
                        continue
                    purls = set()
                    for product in statement.get("products", []):
                        for item in [product, *product.get("subcomponents", [])]:
                            pid = item.get("@id", "")
                            if pid.startswith("pkg:") and not pid.startswith("pkg:oci/"):
                                purls.update(purl_forms(pid.split("?", 1)[0]))
                    if purls:
                        restated = {k: v for k, v in statement.items() if k != "products"}
                        restated["products"] = [{"@id": p} for p in sorted(purls)]
                        statements[json.dumps(restated, sort_keys=True)] = restated
    return list(statements.values())


def cmd_vex(cfg: Config, image: str, version: str, base: str | None, output: str) -> None:
    entry = cfg.entry(image, version)
    ref = cfg.resolve_base(base, entry)
    statements = vendor_vex(ref)
    document = {
        "@context": "https://openvex.dev/ns/v0.2.0",
        "@id": f"{REPOSITORY}/vex/base/{hashlib.sha256(ref.encode()).hexdigest()[:16]}",
        "author": f"The publisher of {ref.split('@', 1)[0]}, re-stated by scripts/images.py",
        "timestamp": "2026-01-01T00:00:00Z",
        "version": 1,
        "statements": statements,
    }
    Path(output).write_text(json.dumps(document, indent=2) + "\n")
    note(f"vex: {len(statements)} vendor statement(s) for {ref.split('@', 1)[0]}")


# Docker Hub repositories -------------------------------------------------------

HUB = "https://hub.docker.com"


def hub_request(method: str, path: str, token: str | None = None, data: dict | None = None) -> tuple[int, dict]:
    headers = {"User-Agent": USER_AGENT, "Content-Type": "application/json", "Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(data).encode() if data is not None else None
    request = urllib.request.Request(f"{HUB}{path}", data=body, method=method, headers=headers)
    try:
        with urlopen(request) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return error.code, json.loads(raw) if raw else {}
        except ValueError:
            return error.code, {"detail": raw.decode(errors="replace")[:200]}


def dockerhub_overview(cfg: Config, image: str) -> str:
    entries = cfg.entries(image)
    latest = cfg.entry(image)
    repos = cfg.repos(image)
    hub_repo = next(r for r in repos if r.startswith("docker.io/"))
    rows = "\n".join(
        f"| {' '.join(f'`{t}`' for t in e.moving_tags())} | {contents(cfg, e)}"
        f"{' (' + e.flavour.capitalize() + ')' if e.flavour else ''} |"
        for e in entries
    )
    return f"""# {hub_repo.removeprefix('docker.io/')}

{cfg.images[image]['description']}. Part of
[Libre DevOps Container Images]({REPOSITORY}): thin, hardened, version-pinned images for CI
jobs and tooling, built on Docker Hardened Images, scanned before and after publishing, and
signed. Every tag has the same digest here and in GHCR (`{repos[0]}`).

## Tags

| Tags | Contents |
| --- | --- |
{rows}

Every version also has a date tag (for example `{latest.date_tag('20261107')}`) that is never
overwritten. Images are multi-platform (linux/amd64 and linux/arm64) and run as uid 10001 in
`/work`.

## Use

```sh
docker pull {hub_repo}:{latest.version}
docker run --rm -v "$PWD:/work" {hub_repo}:{latest.version}
```

## Verify

```sh
cosign verify {hub_repo}:{latest.version} \\
  --certificate-identity {REPOSITORY}/.github/workflows/release.yml@refs/heads/main \\
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Documentation

Usage in GitHub Actions, GitLab CI, Azure DevOps, Podman and Kubernetes; adding a CA bundle;
pinning; the security model; and troubleshooting: [{REPOSITORY}#readme]({REPOSITORY}#readme).
Report vulnerabilities privately: [{REPOSITORY}/security]({REPOSITORY}/security).
"""


def cmd_dockerhub(cfg: Config) -> None:
    """Make sure every image's Docker Hub repository exists, is public, and has
    an up-to-date overview. Creates missing repositories as public (so a first
    push never creates a private one) and never deletes anything."""
    namespaces = [r.removeprefix("docker.io/") for r in cfg.registries if r.startswith("docker.io/")]
    if not namespaces:
        return
    credentials = registry_credentials("docker.io")
    if not credentials:
        raise Failure("no Docker Hub credentials: set DOCKERHUB_USERNAME and DOCKERHUB_TOKEN, or log in to docker.io")
    status, body = hub_request("POST", "/v2/users/login", data={"username": credentials[0], "password": credentials[1]})
    token = body.get("token") or body.get("access_token")
    if status != 200 or not token:
        raise Failure(f"Docker Hub login failed: HTTP {status} {body.get('detail', '')}")
    for namespace in namespaces:
        for image, spec in cfg.images.items():
            short = spec["description"][:100]
            full = dockerhub_overview(cfg, image)
            status, repo = hub_request("GET", f"/v2/namespaces/{namespace}/repositories/{image}", token)
            if status == 404:
                status, body = hub_request(
                    "POST",
                    f"/v2/namespaces/{namespace}/repositories",
                    token,
                    {"namespace": namespace, "name": image, "description": short, "full_description": full, "is_private": False},
                )
                if status not in (200, 201):
                    raise Failure(f"cannot create docker.io/{namespace}/{image}: HTTP {status} {body}")
                note(f"docker.io/{namespace}/{image}: created, public")
                continue
            if status != 200:
                raise Failure(f"cannot read docker.io/{namespace}/{image}: HTTP {status} {repo}")
            if repo.get("is_private"):
                status, body = hub_request(
                    "POST", f"/v2/repositories/{namespace}/{image}/privacy/", token, {"is_private": False}
                )
                if status not in (200, 201, 204):
                    raise Failure(f"docker.io/{namespace}/{image} is private and could not be made public: HTTP {status} {body}")
                note(f"docker.io/{namespace}/{image}: made public")
            if repo.get("description") != short or repo.get("full_description") != full:
                status, body = hub_request(
                    "PATCH", f"/v2/repositories/{namespace}/{image}/", token, {"description": short, "full_description": full}
                )
                if status != 200:
                    raise Failure(f"cannot update docker.io/{namespace}/{image}: HTTP {status} {body}")
                note(f"docker.io/{namespace}/{image}: overview updated")
            status, repo = hub_request("GET", f"/v2/namespaces/{namespace}/repositories/{image}", token)
            if status != 200 or repo.get("is_private"):
                raise Failure(f"docker.io/{namespace}/{image} is not public")
            note(f"docker.io/{namespace}/{image}: public")


# Validation --------------------------------------------------------------------


def cmd_validate(cfg: Config) -> None:
    problems: list[str] = []
    protected = cfg.data.get("protected") or []
    for name, spec in cfg.images.items():
        if any(name == p or name.startswith(p + "/") for p in protected):
            problems.append(f"image '{name}' would reuse a protected package name")
        for key in ("description", "contents", "versions"):
            if key not in spec:
                problems.append(f"image '{name}' has no {key}")
        for tool in spec.get("tools") or []:
            if tool not in cfg.tools:
                problems.append(f"image '{name}' uses '{tool}', which is not under tools")
        for included in spec.get("includes") or []:
            if included not in cfg.images or cfg.images[included].get("includes"):
                problems.append(f"image '{name}' includes '{included}', which is not a plain image")
        for base_name in spec.get("portability") or []:
            if base_name not in cfg.portability:
                problems.append(f"image '{name}' lists portability base '{base_name}', which is not under portability")
        for suite in spec.get("tests") or [name]:
            if not (ROOT / "tests" / f"{suite}.sh").exists():
                problems.append(f"image '{name}' runs tests/{suite}.sh, which does not exist")
        if not re.search(rf"^FROM \S+ AS {re.escape(name)}$", (ROOT / CONTAINERFILE).read_text(), flags=re.M):
            problems.append(f"image '{name}' has no `AS {name}` stage in {CONTAINERFILE}")
        entries = [e for e in cfg.entries() if e.image == name]
        for flavour in sorted({e.flavour or "" for e in entries}):
            latest = [e.key for e in entries if e.latest and (e.flavour or "") == flavour]
            label = f"{name} ({flavour})" if flavour else name
            if len(latest) != 1:
                problems.append(f"image '{label}' needs exactly one latest entry, has {len(latest)}")
        for e in entries:
            if "_" in e.id:
                problems.append(f"{e.id}: ids must not contain _, which separates them from the platform in CI artifact names")
        keys = [e.key for e in entries]
        for key in sorted({k for k in keys if keys.count(k) > 1}):
            problems.append(f"image '{name}' lists {key} twice")
        seen: dict[str, str] = {}
        for raw in spec["versions"]:
            for field in ("version", "python"):
                if field in raw and not isinstance(raw[field], str):
                    problems.append(f"{name}: quote {field} {raw[field]!r}, or YAML reads it as a number")
        for e in entries:
            if e.atop and (e.atop not in cfg.images or e.atop == name):
                problems.append(f"{e.id}: atop '{e.atop}' is not another image")
            if e.base_key not in cfg.bases:
                problems.append(f"{e.id}: base '{e.base_key}' is not under bases")
            for kind in e.moving:
                if kind not in ("minor", "major"):
                    problems.append(f"{e.id}: moving takes minor or major, not '{kind}'")
            for tag in e.moving_tags():
                if tag in seen:
                    problems.append(f"{name}: tag '{tag}' is claimed by {seen[tag]} and {e.key}")
                seen[tag] = e.key
    for src in cfg.terraform_providers:
        if src.split("/")[0] not in PROVIDER_KEYS:
            problems.append(f"terraform_providers: no signing key is pinned for {src} (PROVIDER_KEYS in scripts/images.py)")
    for section, refs in (("bases", cfg.bases), ("portability", cfg.portability)):
        for key, ref in refs.items():
            if not DIGEST.search(ref):
                problems.append(f"{section}.{key} is not pinned by digest; run `just pin`")
    for tool in cfg.common + cfg.ci + ["go"]:
        if tool not in cfg.tools:
            problems.append(f"'{tool}' is listed but not under tools")
    for tool in cfg.ci:
        if tool not in DOWNLOADS:
            problems.append(f"CI tool '{tool}' has no download recipe in scripts/images.py")
    if problems:
        raise Failure("versions.yml has problems:\n  " + "\n  ".join(problems))
    cmd_lock(cfg, check=True)


# Build inputs ------------------------------------------------------------------


# Tools a build installs by version rather than from a pinned download: the
# PowerShell modules, and tfstacks, whose cached copy records its version.
VERSION_ARG_TOOLS = ("az-powershell", "microsoft-graph", "pester", "psscriptanalyzer", "libredevopshelpers", "tfstacks")


def build_args(cfg: Config, entry: Entry, base: str | None = None) -> dict[str, str]:
    lock = load_lock()
    args = {"BASE_IMAGE": cfg.resolve_base(base, entry)}
    if entry.atop:
        args["ATOP"] = entry.atop
    if minor := cfg.python_minor(entry):
        args["PYTHON_MINOR"] = minor
    for c in cfg.components(entry):
        if c.image == "terraform":
            args["TERRAFORM_VERSION"] = c.version
    for tool, version in cfg.downloads(entry):
        args[f"{arg_name(tool)}_ASSET"] = asset_spec(lock, tool, version)
    for tool, version in cfg.go_builds(entry):
        args[f"{arg_name(tool)}_GO"] = go_spec(lock, tool, version)
    for tool in cfg.tools_for(entry):
        if tool in VERSION_ARG_TOOLS:
            args[f"{arg_name(tool)}_VERSION"] = cfg.tools[tool]
    for arg, spec in cfg.python_locks(entry).items():
        if spec["key"] not in lock["python"]:
            raise Failure(f"{spec['key']} is not locked; run `just lock`")
        args[arg] = spec["file"].removeprefix("images/")
    if packages := cfg.os_packages(entry):
        args["OS_PACKAGES"] = " ".join(packages)
    if providers := cfg.providers(entry):
        items = []
        for src, versions in providers.items():
            for v in versions:
                try:
                    assets = lock["providers"][src][v]
                except KeyError:
                    raise Failure(f"provider {src} {v} is not pinned; run `just lock`") from None
                items += [f"{arch}|{src}|{v}|{a['url']}|{a['sha256']}" for arch, a in sorted(assets.items())]
        args["TERRAFORM_PROVIDERS"] = " ".join(items)
    return args


def test_env(cfg: Config, entry: Entry) -> dict[str, str]:
    env = {}
    if minor := cfg.python_minor(entry):
        env["EXPECT_PYTHON"] = minor
    for c in cfg.components(entry):
        if c.image != "python":
            env[f"EXPECT_{arg_name(c.image)}"] = c.version
    for tool in cfg.tools_for(entry):
        env[f"EXPECT_{arg_name(tool)}"] = cfg.tools[tool]
    if providers := cfg.providers(entry):
        env["EXPECT_TERRAFORM_PROVIDERS"] = " ".join(f"{src}={','.join(vs)}" for src, vs in providers.items())
    return env


def labels(cfg: Config, entry: Entry) -> dict[str, str]:
    base_name, _, base_digest = entry.base.partition("@")
    return {
        "org.opencontainers.image.title": entry.image,
        "org.opencontainers.image.description": cfg.images[entry.image]["description"],
        "org.opencontainers.image.version": entry.version,
        "org.opencontainers.image.source": REPOSITORY,
        "org.opencontainers.image.url": REPOSITORY,
        "org.opencontainers.image.documentation": f"{REPOSITORY}#readme",
        "org.opencontainers.image.licenses": "MIT",
        "org.opencontainers.image.vendor": "Libre DevOps",
        "org.opencontainers.image.base.name": base_name,
        "org.opencontainers.image.base.digest": base_digest,
    }


def as_lines(values: dict[str, str]) -> str:
    return "\n".join(f"{k}={v}" for k, v in values.items())


def local_ref(entry: Entry, base: str | None) -> str:
    suffix = f"-{re.sub(r'[^a-z0-9.]+', '-', base.lower()).strip('-')}" if base else ""
    return f"localhost/libre-devops/{entry.image}:{entry.key}{suffix}"[:200]


def cmd_matrix(cfg: Config, github_output: bool) -> None:
    builds, entries, portability = [], [], []
    for e in cfg.entries():
        entries.append({"id": e.id, "image": e.image, "version": e.key})
        for platform, runner in cfg.platforms.items():
            builds.append(
                {
                    "id": e.id,
                    "image": e.image,
                    "version": e.key,
                    "platform": platform,
                    "arch": platform.split("/", 1)[1],
                    "runner": runner,
                    "containerfile": CONTAINERFILE,
                    "target": e.image,
                    "repos": ",".join(cfg.repos(e.image)),
                    "primary_repo": cfg.repos(e.image)[0],
                    "build_args": as_lines(build_args(cfg, e)),
                    "labels": as_lines(labels(cfg, e)),
                }
            )
    for e in (e for e in cfg.entries() if e.latest and not e.flavour):
        for name in cfg.images[e.image].get("portability", list(cfg.portability)):
            portability.append(
                {
                    "id": f"{e.id}-{name}",
                    "image": e.image,
                    "version": e.version,
                    "base_name": name,
                    "platform": "linux/amd64",
                    "arch": "amd64",
                    "runner": cfg.platforms["linux/amd64"],
                    "containerfile": CONTAINERFILE,
                    "target": e.image,
                    "build_args": as_lines(build_args(cfg, e, name)),
                }
            )
    outputs = {
        "builds": {"include": builds},
        "entries": {"include": entries},
        "portability": {"include": portability},
    }
    if github_output:
        with open(os.environ["GITHUB_OUTPUT"], "a") as fh:
            for key, value in outputs.items():
                fh.write(f"{key}={json.dumps(value, separators=(',', ':'))}\n")
    print(json.dumps(outputs, indent=2))


def cmd_tags(cfg: Config, image: str, version: str, date: str) -> None:
    if not re.fullmatch(r"\d{8}", date):
        raise Failure(f"date must be YYYYMMDD, not '{date}'")
    e = cfg.entry(image, version)
    print(json.dumps({"date_tag": e.date_tag(date), "moving": e.moving_tags(), "platforms": len(cfg.platforms)}))


# Docs --------------------------------------------------------------------------


def load_releases() -> dict:
    return json.loads(RELEASES.read_text()) if RELEASES.exists() else {}


def contents(cfg: Config, entry: Entry) -> str:
    values = {k.replace("-", "_"): v for k, v in cfg.tools.items()}
    for c in cfg.components(entry):
        values[c.image.replace("-", "_")] = c.version
    values.update(version=entry.version, python=cfg.python_minor(entry) or "")
    for src, versions in cfg.providers(entry).items():
        values[src.split("/")[1]] = ", ".join(versions)
    return (entry.contents or cfg.images[entry.image]["contents"]).format(**values)


def images_table(cfg: Config) -> str:
    rows = ["| Image | Tags | Base | Contents | Pull |", "| --- | --- | --- | --- | --- |"]
    for e in cfg.entries():
        tags = " ".join(f"`{t}`" for t in e.moving_tags()) + f"<br>`{e.stem}-YYYYMMDD`"
        base = f"`{e.base.split('@', 1)[0]}`"
        pull = "<br>".join(f"`{repo}:{e.key}`" for repo in cfg.repos(e.image))
        rows.append(f"| `{e.image}` | {tags} | {base} | {contents(cfg, e)} | {pull} |")
    common = ", ".join(f"{DISPLAY.get(t, t)} {cfg.tools[t]}" for t in cfg.common)
    platforms = " and ".join(cfg.platforms)
    note_text = (
        f"Every image also has bash, git, curl, ca-certificates, {common}, runs as `app` "
        f"(uid 10001) in `/work`, and is a multi-platform image for {platforms}. "
        f"The Go tools are built from source with Go {cfg.tools['go']}."
    )
    return "\n".join(rows) + "\n\n" + note_text


def digests_table(cfg: Config) -> str:
    releases = load_releases()
    rows = []
    for e in cfg.entries():
        record = releases.get(e.image, {}).get(e.key)
        if record:
            rows.append(
                f"| `{e.image}` | `{e.key}` | `{record['date_tag']}` | `{record['digest']}` | {record['released']} |"
            )
    if not rows:
        return "_No release has been published yet. This table fills in after the first release._"
    header = ["| Image | Version | Newest date tag | Digest | Released |", "| --- | --- | --- | --- | --- |"]
    return "\n".join(header + rows)


def render_readme(cfg: Config) -> str:
    text = HEADER.read_text()
    for marker, body in (
        ("<!-- generated:images -->", images_table(cfg)),
        ("<!-- generated:digests -->", digests_table(cfg)),
    ):
        if text.count(marker) != 1:
            raise Failure(f"HEADER.md must contain {marker} exactly once")
        text = text.replace(marker, body)
    return GENERATED + text


def cmd_docs(cfg: Config, check: bool) -> None:
    rendered = render_readme(cfg)
    if check:
        if not README.exists() or README.read_text() != rendered:
            raise Failure("README.md is out of date; run `just docs`")
        return
    README.write_text(rendered)


def cmd_record(cfg: Config, directory: str) -> None:
    releases = load_releases()
    for path in sorted(Path(directory).glob("*.json")):
        record = json.loads(path.read_text())
        releases.setdefault(record["image"], {})[record["version"]] = {
            key: record[key] for key in ("date_tag", "digest", "released")
        }
    current = {(e.image, e.key) for e in cfg.entries()}
    pruned = {
        image: dict(sorted((v, r) for v, r in versions.items() if (image, v) in current))
        for image, versions in sorted(releases.items())
    }
    pruned = {image: versions for image, versions in pruned.items() if versions}
    RELEASES.write_text(json.dumps(pruned, indent=2) + "\n")


# Entry point -------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("validate")
    p = sub.add_parser("matrix")
    p.add_argument("--github-output", action="store_true")
    for name in ("build-args", "local-ref"):
        p = sub.add_parser(name)
        p.add_argument("image")
        p.add_argument("version", nargs="?", default="")
        p.add_argument("--base", default="")
    for name in ("test-env", "labels"):
        p = sub.add_parser(name)
        p.add_argument("image")
        p.add_argument("version", nargs="?", default="")
    p = sub.add_parser("tags")
    p.add_argument("image")
    p.add_argument("version")
    p.add_argument("date")
    sub.add_parser("repos").add_argument("image")
    sub.add_parser("test-server-image")
    p = sub.add_parser("test-suites")
    p.add_argument("image")
    p.add_argument("version", nargs="?", default="")
    for name in ("lock", "docs"):
        sub.add_parser(name).add_argument("--check", action="store_true")
    sub.add_parser("pin")
    sub.add_parser("dockerhub")
    sub.add_parser("record").add_argument("directory")
    p = sub.add_parser("vex")
    p.add_argument("image")
    p.add_argument("version", nargs="?", default="")
    p.add_argument("--base", default="")
    p.add_argument("-o", "--output", required=True)
    args = parser.parse_args(argv)

    try:
        cfg = Config.load()
        match args.command:
            case "validate":
                cmd_validate(cfg)
            case "matrix":
                cmd_matrix(cfg, args.github_output)
            case "build-args":
                print(as_lines(build_args(cfg, cfg.entry(args.image, args.version), args.base or None)))
            case "local-ref":
                print(local_ref(cfg.entry(args.image, args.version), args.base or None))
            case "test-env":
                print(as_lines(test_env(cfg, cfg.entry(args.image, args.version))))
            case "test-server-image":
                # The pinned base of the newest python image, for the TLS
                # server in the CA trust test (tests/run.sh).
                print(cfg.entry("python").base)
            case "test-suites":
                print("\n".join(cfg.tests(cfg.entry(args.image, args.version))))
            case "labels":
                print(as_lines(labels(cfg, cfg.entry(args.image, args.version))))
            case "tags":
                cmd_tags(cfg, args.image, args.version, args.date)
            case "repos":
                cfg.entries(args.image)
                print("\n".join(cfg.repos(args.image)))
            case "lock":
                cmd_lock(cfg, args.check)
            case "pin":
                cmd_pin(cfg)
            case "dockerhub":
                cmd_dockerhub(cfg)
            case "docs":
                cmd_docs(cfg, args.check)
            case "record":
                cmd_record(cfg, args.directory)
            case "vex":
                cmd_vex(cfg, args.image, args.version, args.base or None, args.output)
    except Failure as failure:
        print(f"images.py: {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
