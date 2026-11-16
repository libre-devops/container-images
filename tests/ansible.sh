# Smoke tests for the ansible image (and the Ansible in ansible-azure).
# shellcheck shell=bash
set -euo pipefail

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
ok() { echo "ok: $*"; }

ansible --version
got=$(/opt/ansible/bin/python -c 'import importlib.metadata as m; print(m.version("ansible-core"))')
[ "$got" = "$EXPECT_ANSIBLE" ] || fail "ansible-core is $got, want $EXPECT_ANSIBLE"
ok "ansible-core $EXPECT_ANSIBLE"

got=$(/opt/ansible/bin/python -c 'import sys; print("%d.%d" % sys.version_info[:2])')
[ "$got" = "$EXPECT_PYTHON" ] || fail "Ansible runs on CPython $got, want $EXPECT_PYTHON"
ok "Ansible runs on CPython $EXPECT_PYTHON"

for command in ansible ansible-playbook ansible-galaxy ansible-doc ansible-vault ansible-inventory ansible-config ansible-lint molecule ssh; do
	command -v "$command" >/dev/null || fail "$command is not on PATH"
done
ok "the ansible commands, ansible-lint, molecule and ssh are on PATH"

version=$(ssh -V 2>&1)
grep -q "^OpenSSH_${EXPECT_OPENSSH}," <<<"$version" || fail "ssh is $version, want OpenSSH $EXPECT_OPENSSH"
ssh-keygen -q -t ed25519 -N '' -f "$(mktemp -u)"
ok "OpenSSH $EXPECT_OPENSSH (built from source) runs and makes keys"

/opt/ansible/bin/python -c 'import jmespath, netaddr, winrm, pip_system_certs; print("jmespath", jmespath.__version__, "netaddr", netaddr.__version__)'
ok "jmespath, netaddr, pywinrm and pip-system-certs import"

cd "$(mktemp -d)"
cat >site.yml <<'YAML'
---
- name: Smoke test
  hosts: localhost
  connection: local
  gather_facts: true
  tasks:
    - name: Check the facts
      ansible.builtin.assert:
        that:
          - ansible_facts.python.version.major == 3
    - name: Write a file
      ansible.builtin.copy:
        content: "ok\n"
        dest: "{{ playbook_dir }}/written.txt"
        mode: "0644"
YAML
ansible-playbook -i localhost, site.yml
[ "$(cat written.txt)" = ok ] || fail "the playbook did not write its file"
ok "a playbook runs against localhost"

ansible-lint --offline --version
ansible-lint --offline site.yml
ok "ansible-lint runs offline"

got=$(ansible-galaxy collection list containers.podman --format json |
	jq -r '[.[] | ."containers.podman".version] | first')
[ "$got" = "$EXPECT_CONTAINERS_PODMAN" ] || fail "containers.podman is $got, want $EXPECT_CONTAINERS_PODMAN"
ok "containers.podman $EXPECT_CONTAINERS_PODMAN"

molecule --version
drivers=$(molecule drivers)
for driver in default podman; do
	grep -qw "$driver" <<<"$drivers" || fail "molecule has no $driver driver: $drivers"
done
ok "molecule has its default driver and molecule-plugins' podman driver"

# An ansible-native scenario (Molecule's own layout) against localhost, with
# no network: converge, idempotence and verify.
mkdir -p molecule/default/inventory
cat >molecule/default/molecule.yml <<'YAML'
---
ansible:
  executor:
    args:
      ansible_playbook:
        - --inventory=${MOLECULE_SCENARIO_DIRECTORY}/inventory/
scenario:
  test_sequence: [converge, idempotence, verify]
YAML
cat >molecule/default/inventory/hosts.yml <<'YAML'
---
all:
  children:
    molecule:
      hosts:
        instance:
          ansible_connection: local
          ansible_python_interpreter: "{{ ansible_playbook_python }}"
YAML
cat >molecule/default/converge.yml <<'YAML'
---
- name: Converge
  hosts: molecule
  gather_facts: false
  tasks:
    - name: Write a file
      ansible.builtin.copy:
        content: "converged\n"
        dest: "{{ playbook_dir }}/converged.txt"
        mode: "0644"
YAML
cat >molecule/default/verify.yml <<'YAML'
---
- name: Verify
  hosts: molecule
  gather_facts: false
  tasks:
    - name: Read the file
      ansible.builtin.slurp:
        src: "{{ playbook_dir }}/converged.txt"
      register: converged
    - name: Check it
      ansible.builtin.assert:
        that: (converged.content | b64decode) == "converged\n"
YAML
molecule test || fail "molecule test failed against localhost"
ok "molecule test runs a scenario against localhost"
