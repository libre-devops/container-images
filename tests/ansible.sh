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

for command in ansible ansible-playbook ansible-galaxy ansible-doc ansible-vault ansible-inventory ansible-config ansible-lint ssh; do
	command -v "$command" >/dev/null || fail "$command is not on PATH"
done
ok "the ansible commands, ansible-lint and ssh are on PATH"

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
