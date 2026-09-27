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

What is not here, on purpose: the tools of the laptop side, such as restic,
come as binaries damstack fetches itself; anything only one stack needs goes
into an image of that stack, built `FROM` this one.

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

Tags `vX.Y.Z` publish `ghcr.io/eugene-panin/damstack-toolbox:X.Y.Z`, `:X.Y`
and `:latest`.

## License

MIT, see [LICENSE](LICENSE).
