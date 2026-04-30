# Pi Agent Docker

Run Pi Agent as a local `pi` command backed by Docker image snapshots.

This package gives Pi a stateful Docker workstation. Before each run, the
current image is tagged as a snapshot. After Pi exits, the container is
committed back to the current image. If the environment gets into a bad state,
roll back to an earlier snapshot.

This does not make projects reproducible. Project reproducibility belongs in
the project repo through its own `Dockerfile`, scripts, `Makefile`, `mise`
config, or other project-owned tooling.

## State

The Docker image stores container-local state:

- Pi installation and login/session state
- `/home/agent`
- apt-installed packages
- npm and pip caches
- other system and user config inside the container

The project directory is bind-mounted under `/workspace/<project-name>`.
Project file changes happen on the host filesystem and are not captured by
`docker commit`.

State is stored in Docker images, not Docker volumes:

```sh
pi-agent-sandbox:base
pi-agent-sandbox:current
pi-agent-sandbox:snap-YYYYMMDD-HHMMSS
```

The Linux variant uses the `pi-agent-sandbox-linux` image repo and passes your
host UID/GID as Docker build args so bind-mounted files are owned by your host
user.

## Security

This setup keeps Pi away from host authority:

- The host home directory is not mounted.
- Host SSH and GPG keys are not mounted.
- Common credential environment variables are cleared.
- `/var/run/docker.sock` is not mounted.
- Pi should not push, sign commits, or control the host Docker daemon.

Run pushes, signing, credentialed commands, and host Docker commands from the
host shell.

The `pi-agent-sandbox:*` and `pi-agent-sandbox-linux:*` images are private local
state. They may contain sensitive Pi/session/config data. Do not push or share
them.

## Install

Run:

```sh
./install.sh
```

The installer copies files to `~/.config/pi-agent-docker` by default. It selects
the Linux variant on Linux and the mac variant elsewhere. It asks for:

- variant: `mac` or `linux`
- install directory
- shell config file to update, such as `~/.zshrc`

Press Enter to accept each default.

Mac source line:

```sh
source "$HOME/.config/pi-agent-docker/pi.zsh"
```

Linux source line:

```sh
source "$HOME/.config/pi-agent-docker/pi-linux.zsh"
```

Reload your shell:

```sh
source ~/.zshrc
```

The first `pi` run builds the base image, creates the current image, installs Pi
inside the container if needed, and runs Pi.

## Usage

Run Pi in the current project:

```sh
pi
```

Pass arguments to Pi after `--`:

```sh
pi -- --help
```

Wrapper flags such as `--help` and `--verbose` are parsed before `--`.

Open a shell in the same environment:

```sh
pi-shell
```

Show config, image state, and mount target:

```sh
pi-status
```

List snapshots:

```sh
pi-snapshots
```

Roll back to a snapshot:

```sh
pi-rollback pi-agent-sandbox:snap-YYYYMMDD-HHMMSS
```

Linux:

```sh
pi-rollback pi-agent-sandbox-linux:snap-YYYYMMDD-HHMMSS
```

Reset current image to the base image:

```sh
pi-reset-system
```

Remove the current image and snapshots:

```sh
pi-reset-all
```

Rebuild the base image:

```sh
pi-rebuild-base
```

Keep only the 10 newest snapshots:

```sh
pi-prune 10
```

By default, `PI_AGENT_AUTO_PRUNE=1` keeps the newest
`PI_AGENT_SNAPSHOT_KEEP=10` snapshots after each run.

## Mounts

Inside a Git repo, the repo root is mounted read/write at
`/workspace/<repo-name>`. Outside a Git repo, the current directory is mounted
at `/workspace/<directory-name>`.

The container working directory is the mounted project directory, not bare
`/workspace`. This keeps resumed Pi sessions scoped to the project path.

## Concurrency

Only one `pi` or `pi-shell` run can be active at a time. Docker enforces this
with a fixed container name:

```sh
pi-agent-active
```

Linux:

```sh
pi-agent-active-linux
```

If a run is killed abruptly, the active container name may remain. Inspect it
first:

```sh
docker ps -a --filter 'name=^/pi-agent-active$'
```

Linux:

```sh
docker ps -a --filter 'name=^/pi-agent-active-linux$'
```

Remove it only if it is stale:

```sh
docker rm pi-agent-active
```

Linux:

```sh
docker rm pi-agent-active-linux
```

## Environment

Defaults:

```sh
PI_AGENT_DOCKER_DIR="$HOME/.config/pi-agent-docker"
PI_AGENT_DOCKERFILE="Dockerfile"
PI_AGENT_IMAGE_REPO="pi-agent-sandbox"
PI_AGENT_BASE_IMAGE="pi-agent-sandbox:base"
PI_AGENT_CURRENT_IMAGE="pi-agent-sandbox:current"
PI_AGENT_ACTIVE_CONTAINER="pi-agent-active"
PI_AGENT_SNAPSHOT_KEEP="10"
PI_AGENT_AUTO_PRUNE="1"
```

Linux defaults:

```sh
PI_AGENT_DOCKERFILE="Dockerfile.linux"
PI_AGENT_HOST_UID="$(id -u)"
PI_AGENT_HOST_GID="$(id -g)"
PI_AGENT_IMAGE_REPO="pi-agent-sandbox-linux"
PI_AGENT_BASE_IMAGE="pi-agent-sandbox-linux:base"
PI_AGENT_CURRENT_IMAGE="pi-agent-sandbox-linux:current"
PI_AGENT_ACTIVE_CONTAINER="pi-agent-active-linux"
```

If your Linux UID/GID changes, rebuild the base image and reset current state so
the image's `agent` user matches your host user again.

Credential variables cleared inside the container:

```sh
GITHUB_TOKEN
GH_TOKEN
SSH_AUTH_SOCK
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
GOOGLE_APPLICATION_CREDENTIALS
KUBECONFIG
NPM_TOKEN
```
