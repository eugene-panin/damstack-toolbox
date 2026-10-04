# damstack-toolbox

The tools [damstack](https://github.com/eugene-panin/damstack) runs the steps
of a stack with, and nothing more:

| Tool | Version | For |
|---|---|---|
| ansible-core, with Python 3.13 and PyYAML | 2.21.4 | setting up servers |
| OpenTofu | 1.12.6 | resources in the APIs of Nomad, Consul, Vault, DNS providers |
| Conftest | 0.70.1 | checking every plan against the policies of a stack |
| git | from Alpine | OpenTofu fetches every module over git, from the registry too |
| openssh-client | from Alpine | Ansible reaches servers over SSH |

On Alpine 3.24, about 290 MB, for amd64 and arm64. OpenTofu and Conftest are
checked against their SHA-256 when the image is built.

Anything only one stack needs goes into an image of that stack, built `FROM`
this one.

## The native toolbox

The same tools, and restic, without Docker, for the Mac damstack runs on:
`damstack-toolbox-<version>-darwin-<arm64|amd64>.tar.gz`, with `SHA256SUMS`,
in the release of every tag. damstack fetches the one of its
machine into its cache, checks it, and runs every step with it.

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

## Running as any user

damstack runs the image as the user who calls it, so that files in the
project stay theirs. ssh refuses to run for a user missing from
`/etc/passwd`, so the entrypoint adds one for the current user when there is
none. `/etc/passwd` is writable for that reason; the container runs one step
and is gone.

`HOME` is `/home/damstack`, writable by anyone, and the working directory
`/work`, where damstack mounts the project.

## Tested

[`test/smoke.sh`](test/smoke.sh), in CI on native amd64 and arm64 runners,
checks that:

- every tool is at its pinned version, and none of the ones left out is there;
- as an arbitrary user, ssh finds that user and the home directory is
  writable;
- Ansible runs; OpenTofu fetches a module from the registry over git and its
  provider, and validates; Conftest verifies a policy with its tests.

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

Tags `vX.Y.Z` publish `ghcr.io/eugene-panin/damstack-toolbox:X.Y.Z`, `:X.Y`
and `:latest`.

## License

MIT, see [LICENSE](LICENSE).
