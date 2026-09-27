#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: smoke.sh <image>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
uid="$(id -u):$(id -g)"
run() { docker run --rm --user "$uid" -v "$work:/work" "$image" "$@"; }
step() { printf '\n== %s\n' "$*"; }

step "pinned versions"
docker run --rm "$image" sh -c '
  tofu version | grep -q "^OpenTofu v1.12.6$"
  ansible --version | grep -q "core 2.21.4"
  conftest --version | grep -q "Conftest: 0.70.1"
  python3 -c "import yaml; assert yaml.__version__ == \"6.0.3\""
  git --version && ssh -V'

step "nothing else"
docker run --rm "$image" sh -c 'for tool in make restic go jq kubectl helm boilerplate; do
  if command -v "$tool" >/dev/null; then echo "$tool is in the image" >&2; exit 1; fi
done'

step "the user who owns the project, unknown to the image: a passwd entry for ssh, a writable home"
docker run --rm --user 4242:4242 --entrypoint sh "$image" -c 'ssh -G example.org >/dev/null 2>&1' \
  && { echo "ssh ran for a user missing from /etc/passwd; the check below would prove nothing" >&2; exit 1; }
run sh -c 'whoami && ssh -G example.org | grep -qx "user damstack" && touch "$HOME/probe"'

step "ansible runs as that user"
run ansible localhost -c local -m ansible.builtin.ping | grep -q '"ping": "pong"'

step "tofu fetches a module from the registry over git, and its provider"
mkdir -p "$work/tofu"
cat >"$work/tofu/main.tf" <<'TF'
module "dns" {
  source  = "eugene-panin/hashistack/nomad//modules/dns-cloudflare"
  version = "~> 0.7"
  records = [{ "example.org" = [{ type = "A", name = "example.org", content = "192.0.2.1" }] }]
}
TF
docker run --rm --user "$uid" -v "$work:/work" -w /work/tofu "$image" sh -c 'tofu init -input=false -no-color >/dev/null && tofu validate -no-color'

step "conftest verifies a policy"
mkdir -p "$work/policy"
cat >"$work/policy/deny.rego" <<'REGO'
package main

deny contains "no name" if not input.name
REGO
cat >"$work/policy/deny_test.rego" <<'REGO'
package main

test_named if count(deny) == 0 with input as {"name": "x"}
test_unnamed if count(deny) == 1 with input as {}
REGO
run conftest verify --policy policy

printf '\nall checks passed for %s\n' "$image"
