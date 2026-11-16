# Smoke tests for the cicd-helper image: the Galaxy roles, and everything
# each declares it needs; the collections and libraries they use; pytest and
# JUnit reports; the extra tools; and what the image leaves out. The Ansible,
# Azure CLI, Terraform (with the provider mirror) and PowerShell suites run
# too.
# shellcheck shell=bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

listed=$(ansible-galaxy role list 2>/dev/null)
for pair in $EXPECT_ANSIBLE_ROLES; do
	name=${pair%%=*}
	version=${pair#*=}
	grep -qxF -- "- $name, $version" <<<"$listed" || fail "role $name $version is not installed: $listed"
done
ok "the roles, at their pinned versions: $EXPECT_ANSIBLE_ROLES"

# What each role says it needs, in its requirements.yml and meta/main.yml, is
# installed: so a new role that needs another collection fails here, in its
# pull request, rather than at run time.
/opt/ansible/bin/python - <<'PY'
import json
import subprocess
import sys
from pathlib import Path

import yaml
from ansible.galaxy.dependency_resolution.versioning import meets_requirements

listing = json.loads(subprocess.check_output(["ansible-galaxy", "collection", "list", "--format", "json"]))
collections = {}
for found in listing.values():
    for name, info in found.items():
        collections.setdefault(name, info["version"])
roles_dir = Path("/usr/share/ansible/roles")
roles = {p.name for p in roles_dir.iterdir()}
problems = []
for role in sorted(roles_dir.iterdir()):
    wanted = []
    requirements = role / "requirements.yml"
    if requirements.exists():
        data = yaml.safe_load(requirements.read_text()) or {}
        if isinstance(data, list):
            data = {"roles": data}
        for item in data.get("collections") or []:
            item = item if isinstance(item, dict) else {"name": item}
            wanted.append((item["name"], str(item.get("version", "*"))))
        for item in data.get("roles") or []:
            name = item if isinstance(item, str) else item.get("name") or item.get("src")
            if name not in roles:
                problems.append(f"{role.name} needs role {name}, which is not installed")
    meta = yaml.safe_load((role / "meta" / "main.yml").read_text()) or {}
    wanted += [(name, "*") for name in meta.get("collections") or [] if name not in ("ansible.builtin", "ansible.legacy")]
    for item in meta.get("dependencies") or []:
        name = item if isinstance(item, str) else item.get("role") or item.get("name")
        if name not in roles:
            problems.append(f"{role.name} depends on role {name}, which is not installed")
    for name, spec in wanted:
        if name not in collections:
            problems.append(f"{role.name} needs collection {name} {spec}, which is not installed")
        elif not meets_requirements(collections[name], spec):
            problems.append(f"{role.name} needs collection {name} {spec}, but {collections[name]} is installed")
if problems:
    sys.exit("FAIL: " + "; ".join(problems))
PY
ok "every role's requirements.yml and meta dependencies are met"

for pair in "community.general=$EXPECT_COMMUNITY_GENERAL" "ansible.posix=$EXPECT_ANSIBLE_POSIX" \
	"theforeman.foreman=$EXPECT_THEFOREMAN_FOREMAN"; do
	name=${pair%%=*}
	want=${pair#*=}
	got=$(ansible-galaxy collection list "$name" --format json | jq -r --arg n "$name" '[.[] | .[$n].version] | first')
	[ "$got" = "$want" ] || fail "$name is $got, want $want"
done
ok "community.general $EXPECT_COMMUNITY_GENERAL, ansible.posix $EXPECT_ANSIBLE_POSIX and theforeman.foreman $EXPECT_THEFOREMAN_FOREMAN"

for module in community.general.zypper ansible.posix.authorized_key theforeman.foreman.content_upload; do
	ansible-doc "$module" >/dev/null || fail "ansible-doc cannot find $module"
done
ok "the roles' collection modules resolve"

# Every role found by name, and its statically imported tasks parsed.
cd "$(mktemp -d)"
{
	echo "---"
	echo "- name: Every role"
	echo "  hosts: localhost"
	echo "  gather_facts: false"
	echo "  roles:"
	for pair in $EXPECT_ANSIBLE_ROLES; do
		echo "    - ${pair%%=*}"
	done
} >site.yml
ansible-playbook -i localhost, --syntax-check site.yml >/dev/null || fail "a playbook using every role fails its syntax check"
ok "a playbook that uses every role passes its syntax check"

/opt/ansible/bin/python -c 'import requests, yaml, zstandard; print("requests", requests.__version__, "zstandard", zstandard.__version__)'
ok "the libraries the roles' modules import on the controller are there"
rpm --version
ok "rpm, which theforeman.foreman reads RPM headers with, runs"

cat >test_smoke.py <<'PY'
from ansible.module_utils.basic import AnsibleModule


def test_ansible_imports():
    assert AnsibleModule
PY
pytest -q -p no:cacheprovider --junitxml=pytest.xml test_smoke.py || fail "pytest cannot run a test that imports Ansible"
grep -q '<testsuite[^>]* tests="1"' pytest.xml || fail "pytest wrote no JUnit report"
ok "pytest runs tests against Ansible's own libraries, and writes JUnit XML"

printf '%s\n' '- name: JUnit' '  hosts: localhost' '  connection: local' '  gather_facts: false' \
	'  tasks:' '    - name: Ping' '      ansible.builtin.ping:' >junit.yml
ANSIBLE_CALLBACKS_ENABLED=ansible.builtin.junit JUNIT_OUTPUT_DIR="$PWD/junit" \
	ansible-playbook -i localhost, junit.yml >/dev/null
grep -qs '<testsuite' junit/*.xml || fail "Ansible's junit callback wrote no report"
ok "Ansible's junit callback writes JUnit XML"

python3 -c 'import requests; print("requests", requests.__version__)'
ok "the image's own python3 has Requests"

got=$(yq --version)
grep -q "v$EXPECT_YQ\$" <<<"$got" || fail "yq is $got, want $EXPECT_YQ"
[ "$(yq '.a.b' <<<'a: {b: ok}')" = ok ] || fail "yq cannot read YAML"
got=$(just --version)
[ "$got" = "just $EXPECT_JUST" ] || fail "just is $got, want $EXPECT_JUST"
for command in yamllint sshpass rsync zip unzip; do
	command -v "$command" >/dev/null || fail "$command is not on PATH"
done
ok "yq $EXPECT_YQ, just $EXPECT_JUST, yamllint, sshpass, rsync, zip and unzip"

# What it leaves out.
for command in ldo podman; do
	! command -v "$command" >/dev/null || fail "$command is in the image, which should do without it"
done
[ ! -e /opt/ldo-cli ] || fail "/opt/ldo-cli is in the image"
pwsh -NoLogo -NoProfile -NonInteractive -Command 'if (Get-Module -ListAvailable LibreDevOpsHelpers) { exit 1 }' ||
	fail "LibreDevOpsHelpers is installed"
ok "no ldo-cli, LibreDevOpsHelpers or Podman"
