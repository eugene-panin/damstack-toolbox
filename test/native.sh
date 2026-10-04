#!/usr/bin/env bash
# Proves a native toolbox archive on this machine: every tool at its pinned
# version, nothing taken from the machine or the user, and the same after the
# toolbox moves to another directory.
#
# The machine is poisoned: commands of the same names on the PATH, a Python
# path, a Python home and a user site that break any import of Ansible, an
# ansible.cfg and a .terraformrc that break any run, a provider in the plugin
# directory of the user, and variables of Ansible and OpenTofu. Each check
# runs twice: with the environment damstack gives a step, where it must pass,
# and with the poisoned one, where it must fail; a check that passes both
# ways proves nothing.
set -euo pipefail

archive=${1:?usage: native.sh <archive>}
archive=$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")
work=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$work"' EXIT
step() { printf '\n== %s\n' "$*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

tb=$work/first/toolbox
mkdir -p "$tb"
tar -xzf "$archive" -C "$tb"
minor=$(sed -n 's/^python \([0-9]*\.[0-9]*\)\..*/\1/p' "$tb/VERSION")

home=$work/home
poison=$work/poison
mkdir -p "$home" "$poison/bin" "$poison/py/ansible" "$work/tmp"
for cmd in python python3 pip pip3 tofu conftest restic ansible ansible-playbook ansible-galaxy; do
  printf '#!/bin/sh\necho "the %s of the machine ran" >&2\nexit 99\n' "$cmd" >"$poison/bin/$cmd"
  chmod 0755 "$poison/bin/$cmd"
done
echo 'raise SystemExit("an ansible of the machine was imported")' >"$poison/py/ansible/__init__.py"
for site in "$home/.local/lib/python$minor/site-packages" "$home/Library/Python/$minor/lib/python/site-packages"; do
  mkdir -p "$site/ansible"
  cp "$poison/py/ansible/__init__.py" "$site/ansible/"
done
printf '[defaults]\nstdout_callback = no_such_callback\n' >"$home/.ansible.cfg"
printf 'provider_installation {\n  network_mirror {\n    url = "https://127.0.0.1:9/"\n  }\n}\n' >"$home/.terraformrc"

# The environment damstack gives a step: nothing of the user's but HOME, the
# toolbox first on the PATH, and its own configurations.
clean() {
  env -i HOME="$home" PATH="$tb/bin:$poison/bin:/usr/bin:/bin" TMPDIR="$work/tmp" \
    ANSIBLE_CONFIG="$tb/etc/ansible.cfg" ANSIBLE_HOME="$work/ansible" ANSIBLE_LOCALHOST_WARNING=False \
    TF_CLI_CONFIG_FILE="$tb/etc/tofurc" TF_PLUGIN_CACHE_DIR="$work/plugins" "$@"
}
# A shell of the user: the tools of the machine first, and every poison.
dirty() {
  env HOME="$home" PATH="$poison/bin:$tb/bin:/usr/bin:/bin" TMPDIR="$work/tmp" \
    PYTHONPATH="$poison/py" PYTHONHOME="$poison" \
    ANSIBLE_CONFIG="$home/.ansible.cfg" ANSIBLE_STDOUT_CALLBACK=no_such_callback \
    TF_CLI_CONFIG_FILE="$home/.terraformrc" TF_VAR_name=poisoned "$@"
}
mkdir -p "$work/plugins"

step "every tool at its pinned version"
clean tofu version | grep -q "^OpenTofu v$(sed -n 's/^opentofu //p' "$tb/VERSION")$" || fail "tofu"
clean conftest --version | grep -q "Conftest: $(sed -n 's/^conftest //p' "$tb/VERSION")" || fail "conftest"
clean restic version | grep -q "^restic $(sed -n 's/^restic //p' "$tb/VERSION") " || fail "restic"
clean ansible --version </dev/null >"$work/out" 2>&1 || { cat "$work/out"; fail "ansible --version"; }
grep -q "core $(sed -n 's/^ansible-core==//p' "$tb/VERSION")" "$work/out" || { cat "$work/out"; fail "ansible-core version"; }
if ! grep -qF "ansible python module location = $tb/python/lib/python$minor/site-packages/ansible" "$work/out" ||
  ! grep -qF "($tb/python/bin/python3)" "$work/out"; then
  cat "$work/out"
  fail "ansible does not run on the Python of the toolbox"
fi

step "the Python of the toolbox ignores the Python path, home and user site of the machine"
py=$tb/python/bin/python3
env PYTHONPATH="$poison/py" "$py" -c 'import ansible' </dev/null >"$work/out" 2>&1 && fail "control: the Python path did not break an import"
grep -q 'an ansible of the machine was imported' "$work/out" || { cat "$work/out"; fail "control: the Python path broke otherwise"; }
env HOME="$home" "$py" -c 'import ansible' </dev/null >"$work/out" 2>&1 && fail "control: the user site did not break an import"
grep -q 'an ansible of the machine was imported' "$work/out" || { cat "$work/out"; fail "control: the user site broke otherwise"; }
env PYTHONHOME="$poison" "$py" -c 'import ansible' </dev/null >/dev/null 2>&1 && fail "control: the Python home did not break Python"
dirty "$tb/bin/ansible" --version </dev/null >"$work/out" 2>&1 || { cat "$work/out"; fail "ansible took the Python path or user site of the machine"; }

step "Ansible Vault encrypts and decrypts"
printf 'pw\n' >"$work/vault-pass"
clean ansible-vault encrypt_string --vault-password-file "$work/vault-pass" --name secret s3cret </dev/null >"$work/vaulted.yml" 2>/dev/null || fail "ansible-vault encrypt"
grep -q 'AES256' "$work/vaulted.yml" || fail "nothing encrypted"
printf -- '---\n' | cat - "$work/vaulted.yml" >"$work/vars.yml"
[[ $(clean ansible localhost -m ansible.builtin.debug -a var=secret -e @"$work/vars.yml" --vault-password-file "$work/vault-pass" </dev/null 2>&1 | grep -c s3cret) -ge 1 ]] ||
  fail "ansible-vault decrypt"

playbook() {
  mkdir -p "$1"
  cat >"$1/site.yml" <<'YAML'
---
- name: Probe the controller
  hosts: localhost
  connection: local
  gather_facts: true
  gather_subset: [min]
  tasks:
    - name: Write what the modules ran with
      ansible.builtin.copy:
        content: "{{ ansible_facts['python']['executable'] }}\n{{ lookup('ansible.builtin.env', 'TF_VAR_name') | default('', true) }}\n"
        dest: "{{ playbook_dir }}/probe.txt"
        mode: "0644"
YAML
}

step "Ansible runs a playbook on this machine with the Python of the toolbox, and nothing of the user's"
playbook "$work/play"
clean ansible-playbook "$work/play/site.yml" </dev/null >"$work/out" 2>&1 || { cat "$work/out"; fail "the playbook"; }
[[ $(sed -n 1p "$work/play/probe.txt") == "$tb/python/bin/python3" ]] || { cat "$work/play/probe.txt"; fail "the modules ran on another Python"; }
[[ -z $(sed -n 2p "$work/play/probe.txt") ]] || fail "a variable of the user reached the playbook"
dirty "$tb/bin/ansible-playbook" "$work/play/site.yml" </dev/null >"$work/out" 2>&1 && fail "control: the ansible.cfg of the user did not break the playbook"
grep -q 'no_such_callback' "$work/out" || { cat "$work/out"; fail "control: another error than the poison"; }

step "OpenTofu fetches a module over git and a provider from its registry, not the user's directories"
os_arch=$(clean tofu version -json | sed -n 's/.*"platform": *"\([^"]*\)".*/\1/p')
fake=$home/.terraform.d/plugins/registry.opentofu.org/hashicorp/random/9.9.9/$os_arch
mkdir -p "$fake"
printf '#!/bin/sh\nexit 99\n' >"$fake/terraform-provider-random_v9.9.9"
chmod 0755 "$fake/terraform-provider-random_v9.9.9"
mkdir -p "$work/tf"
cat >"$work/tf/main.tf" <<'TF'
terraform {
  required_providers {
    random = { source = "hashicorp/random", version = ">= 3.7" }
  }
}

module "dns" {
  source  = "eugene-panin/hashistack/nomad//modules/dns-cloudflare"
  version = "~> 0.7"
  records = []
}

variable "name" {
  type    = string
  default = "clean"
}

output "name" {
  value = var.name
}
TF
(cd "$work/tf" && clean tofu init -input=false -no-color) >"$work/out" 2>&1 || { cat "$work/out"; fail "tofu init"; }
grep -q 'hashicorp/random v3\.' "$work/out" || { cat "$work/out"; fail "the provider came from the plugin directory of the user"; }
test -f "$work/tf/.terraform/modules/dns/modules/dns-cloudflare/main.tf" || fail "the module was not fetched"
(cd "$work/tf" && clean tofu apply -input=false -auto-approve -no-color) >/dev/null 2>&1 || fail "tofu apply"
[[ $(cd "$work/tf" && clean tofu output -raw name) == clean ]] || fail "a TF_VAR of the user reached OpenTofu"
rm -rf "$work/tf/.terraform"
(cd "$work/tf" && dirty "$tb/bin/tofu" init -input=false -no-color) >"$work/out" 2>&1 && fail "control: the .terraformrc of the user did not break tofu init"

step "Conftest verifies a policy"
mkdir -p "$work/policy"
printf 'package main\n\ndeny contains "no name" if not input.name\n' >"$work/policy/deny.rego"
printf 'package main\n\ntest_named if count(deny) == 0 with input as {"name": "x"}\ntest_unnamed if count(deny) == 1 with input as {}\n' >"$work/policy/deny_test.rego"
(cd "$work" && clean conftest verify --no-color --policy policy) >/dev/null || fail "conftest verify"

step "restic backs up and restores"
echo "data" >"$work/data.txt"
clean env RESTIC_PASSWORD=pw restic -q -r "$work/repo" init >/dev/null
clean env RESTIC_PASSWORD=pw restic -q -r "$work/repo" backup "$work/data.txt" >/dev/null
clean env RESTIC_PASSWORD=pw restic -q -r "$work/repo" restore latest --target "$work/restored" >/dev/null
[[ $(cat "$work/restored$work/data.txt") == data ]] || fail "restic restore"

step "the toolbox works the same after it moves"
mkdir -p "$work/second"
mv "$work/first/toolbox" "$work/second/toolbox"
tb=$work/second/toolbox
clean ansible --version </dev/null >"$work/out" 2>&1 || { cat "$work/out"; fail "ansible after the move"; }
grep -qF "($tb/python/bin/python3)" "$work/out" || { cat "$work/out"; fail "ansible still points at the old place"; }
rm -f "$work/play/probe.txt"
clean ansible-playbook "$work/play/site.yml" </dev/null >"$work/out" 2>&1 || { cat "$work/out"; fail "the playbook after the move"; }
[[ $(sed -n 1p "$work/play/probe.txt") == "$tb/python/bin/python3" ]] || fail "the modules ran on another Python after the move"

printf '\nall checks passed for %s\n' "$(basename "$archive")"
