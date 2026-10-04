#!/usr/bin/env bash
# Builds the native toolbox for one platform: a Python of its own with
# ansible-core in it, OpenTofu, Conftest and restic, every download checked
# against its SHA-256, into <out>/damstack-toolbox-<version>-<os>-<arch>.tar.gz.
# Any platform builds on any machine; it needs curl, unzip, bzip2 and uv.
set -euo pipefail

usage() { echo "usage: build.sh <version> <darwin|linux> <amd64|arm64> <out>" >&2; exit 2; }
[[ $# -eq 4 ]] || usage
version=$1 os=$2 arch=$3 out=$4
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=versions.env
. "$here/versions.env"

case "$os-$arch" in
  darwin-arm64) triple=aarch64-apple-darwin conftest_platform=Darwin_arm64 ;;
  darwin-amd64) triple=x86_64-apple-darwin conftest_platform=Darwin_x86_64 ;;
  linux-arm64) triple=aarch64-unknown-linux-gnu conftest_platform=Linux_arm64 ;;
  linux-amd64) triple=x86_64-unknown-linux-gnu conftest_platform=Linux_x86_64 ;;
  *) usage ;;
esac
key=$(echo "${os}_${arch}" | tr '[:lower:]' '[:upper:]')
sum() { local name="${1}_SHA256_${key}"; echo "${!name}"; }

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fetch() {
  local url=$1 want=$2 file
  file="$work/dl/$(basename "$url")"
  mkdir -p "$work/dl"
  curl -fsSL --retry 3 -o "$file" "$url"
  local got
  got=$(sha256 "$file")
  if [[ $got != "$want" ]]; then
    echo "$url does not match its SHA-256: got $got, want $want" >&2
    exit 1
  fi
  echo "$file"
}

root="$work/toolbox"
mkdir -p "$root/bin" "$root/etc"

python=$(fetch "https://github.com/astral-sh/python-build-standalone/releases/download/$PYTHON_RELEASE/cpython-$PYTHON_VERSION+$PYTHON_RELEASE-$triple-install_only_stripped.tar.gz" "$(sum PYTHON)")
tar -xzf "$python" -C "$root"
minor=${PYTHON_VERSION%.*}
site="$root/python/lib/python$minor/site-packages"
uv pip install --quiet --target "$site" --python-platform "$triple" --python-version "$minor" \
  --only-binary :all: --require-hashes --no-deps -r "$here/requirements.lock"
rm -rf "$site"/pip "$site"/pip-*.dist-info "$root"/python/bin/pip*
find "$root/python" -name __pycache__ -type d -prune -exec rm -rf {} +

tofu=$(fetch "https://github.com/opentofu/opentofu/releases/download/v$TOFU_VERSION/tofu_${TOFU_VERSION}_${os}_${arch}.zip" "$(sum TOFU)")
unzip -q -o "$tofu" tofu -d "$root/bin"

conftest=$(fetch "https://github.com/open-policy-agent/conftest/releases/download/v$CONFTEST_VERSION/conftest_${CONFTEST_VERSION}_${conftest_platform}.tar.gz" "$(sum CONFTEST)")
tar -xzf "$conftest" -C "$root/bin" conftest

restic=$(fetch "https://github.com/restic/restic/releases/download/v$RESTIC_VERSION/restic_${RESTIC_VERSION}_${os}_${arch}.bz2" "$(sum RESTIC)")
bunzip2 -c "$restic" >"$root/bin/restic"

for cli in ansible ansible-config ansible-console ansible-doc ansible-galaxy ansible-inventory ansible-playbook ansible-pull ansible-vault; do
  module=${cli#ansible-}
  [[ $cli == ansible ]] && module=adhoc
  cat >"$root/bin/$cli" <<EOF
#!/bin/sh
# $cli of the toolbox: its own Python, isolated from the user's (-I), in UTF-8.
root=\$(CDPATH= cd -- "\$(dirname -- "\$0")/.." && pwd)
exec "\$root/python/bin/python3" -I -X utf8 -m ansible.cli.$module "\$@"
EOF
done
chmod 0755 "$root"/bin/*

cat >"$root/etc/tofurc" <<'EOF'
# The OpenTofu CLI configuration of the toolbox: providers come from their
# registries only, never from the plugin directories of the user.
provider_installation {
  direct {}
}
EOF
: >"$root/etc/ansible.cfg"

cat >"$root/VERSION" <<EOF
damstack-toolbox $version $os/$arch
python $PYTHON_VERSION ($PYTHON_RELEASE)
$(cd "$site" && for d in *.dist-info; do echo "${d%.dist-info}"; done | sed 's/-\([^-]*\)$/==\1/; s/_/-/g' | tr '[:upper:]' '[:lower:]')
opentofu $TOFU_VERSION
conftest $CONFTEST_VERSION
restic $RESTIC_VERSION
EOF

mkdir -p "$out"
archive="$out/damstack-toolbox-$version-$os-$arch.tar.gz"
tar -czf "$archive" -C "$root" .
echo "$archive"
