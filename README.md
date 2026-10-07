# damstack-toolbox

The tools [damstack](https://github.com/eugene-panin/damstack) runs the steps
of a stack with, and nothing more, built for the Mac damstack runs on:
`damstack-toolbox-<version>-darwin-<arm64|amd64>.tar.gz`, with `SHA256SUMS`,
in the release of every tag. damstack fetches the one of its machine into its
cache, checks it, and runs every step with it.

The versions of the tools are in [`native/versions.env`](native/versions.env)
and [`native/requirements.lock`](native/requirements.lock).

## What is in it

```
bin/        tofu, conftest, restic, and ansible-* run on the Python below
python/     Python 3.13 of python-build-standalone, with ansible-core in it
etc/        tofurc and an empty ansible.cfg, the configurations of the toolbox
VERSION     the version of everything in it
```

[`native/build.sh`](native/build.sh) builds either on any machine: every
download is checked against its SHA-256 in
[`native/versions.env`](native/versions.env), and the Python packages are
installed from wheels by the hashes of
[`native/requirements.lock`](native/requirements.lock).

It takes nothing from the machine but `git`, which OpenTofu fetches modules
with, and `ssh`. Two things keep it apart from the user's own tools:

- `ansible-*` run their Python with `-I`: it ignores `PYTHONPATH`,
  `PYTHONHOME` and every other `PYTHON*` variable, and the user's site
  packages.
- damstack gives every step an environment of its own, not the user's
  shell: `HOME`, `PATH` with `bin/` of the toolbox first, `TMPDIR`, and
  `ANSIBLE_CONFIG` (the stack's, or `etc/ansible.cfg`), `ANSIBLE_HOME`,
  `TF_CLI_CONFIG_FILE=etc/tofurc` and `TF_PLUGIN_CACHE_DIR`. `etc/tofurc`
  installs providers from their registries only, never from the plugin
  directories of the user.

cryptography builds for Intel Macs up to 48.0.1; they have it, Apple silicon
the latest.

## Tested

[`test/native.sh`](test/native.sh), in CI on macOS, the amd64 archive under
Rosetta, poisons the machine first: commands of
the same names on the `PATH`, a Python path, home and user site that break
any import of Ansible, an `ansible.cfg` and a `.terraformrc` of the user that
break any run, a provider in the user's plugin directory, `TF_VAR_*`. Then it
checks, each with a control that must fail in the user's environment, that:

- every tool is at its pinned version, and Ansible runs on the Python of the
  toolbox, its modules too;
- Ansible Vault encrypts and decrypts, and a playbook runs;
- OpenTofu fetches a module over git and its provider from the registry, and
  no variable of the user reaches it;
- Conftest verifies a policy, restic backs up and restores;
- all of it works the same after the toolbox moves to another directory.

The images of versions up to 1.1.0 stay on
`ghcr.io/eugene-panin/damstack-toolbox`; no new ones are made.

## License

MIT, see [LICENSE](LICENSE).
