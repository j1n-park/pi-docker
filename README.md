# Pi Agent Docker

Run Pi Agent as a local `pi` command backed by Docker image snapshots.

This package gives Pi a stateful Docker workstation. Multiple Pi sessions share
one Docker container. When the final session exits, the wrapper tags the prior
image as a snapshot and commits the shared container back to the current image.
If the environment gets into a bad state, roll back to an earlier snapshot.

This does not make projects reproducible. Project reproducibility belongs in
the project repo through its own `Dockerfile`, scripts, `Makefile`, `mise`
config, or other project-owned tooling.

Related writing: [Pi Agent: Local and Contained](https://tjpark.dev/thoughts/pi-agent-local-contained/).

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

Each commit adds a Docker image layer. To avoid Docker's layer-depth limit, the
wrapper automatically flattens the current image with `docker export` and
`docker import` when it reaches `PI_AGENT_FLATTEN_LAYER_THRESHOLD`. Flattening
preserves container-local filesystem state but does not include the bind-mounted
project directory.

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

Open a Zsh shell in the same environment. The image includes Zap with its
default `~/.zshrc`:

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

Flatten the current image manually:

```sh
pi-flatten
```

Save and stop an idle shared container after an interrupted session:

```sh
pi-quick-fix --verbose
```

`pi-quick-fix` removes stale session markers, tags the previous current image as
a rollback snapshot, commits the shared container filesystem to the current
image, and removes the container. It refuses to stop the container if a live
`pi` or `pi-shell` session still exists. If there is no shared container, it
only verifies that the lifecycle lock is available.

The `lifecycle.lock` file is intentionally persistent. `flock` releases the
kernel lock when its file descriptor closes; deleting the file can split
concurrent processes across different inodes and must not be used to unlock it.

By default, `PI_AGENT_AUTO_PRUNE=1` keeps the newest
`PI_AGENT_SNAPSHOT_KEEP=10` snapshots after the shared container is committed.

## Mounts

The shared container mounts `PI_AGENT_WORKSPACE_ROOT` read/write at
`/workspace`. By default this is `$HOME/workspace`. Every project opened by
`pi` or `pi-shell` must be below this root; a project keeps its corresponding
path below `/workspace`.

For example, with `PI_AGENT_WORKSPACE_ROOT=$HOME/workspace`, running Pi in
`$HOME/workspace/api` starts it in `/workspace/api`. Set the variable before
sourcing the wrapper if your projects live elsewhere. The root is the only host
directory mounted into the container, so choose a directory containing only
projects you intend Pi to access.

## Concurrency

Several `pi` and `pi-shell` sessions can run concurrently. They use `docker
exec` against one shared container:

```sh
pi-agent-active
```

Linux:

```sh
pi-agent-active-linux
```

The wrapper serializes only lifecycle work: starting the shared container,
deciding that the final session exited, snapshotting, committing, and removing
the container. Pi commands, installs, and updates inside the container are not
globally locked.

If a terminal is force-killed, its host-side session marker is reconciled from
the container on the next session exit. Inspect the count with `pi-status` if
the container appears to remain in use unexpectedly. Inspect the container
first:

```sh
docker ps -a --filter 'name=^/pi-agent-active$'
```

Linux:

```sh
docker ps -a --filter 'name=^/pi-agent-active-linux$'
```

If it is stale, save its container-local state and remove it through the
lifecycle recovery command:

```sh
pi-quick-fix --verbose
```

If committing the final session fails, the wrapper leaves the shared container
in place so its container-local changes can be recovered or the commit retried.
Do not remove a container reported as containing uncommitted state.

## Environment

Defaults:

```sh
PI_AGENT_DOCKER_DIR="$HOME/.config/pi-agent-docker"
PI_AGENT_DOCKERFILE="Dockerfile"
PI_AGENT_IMAGE_REPO="pi-agent-sandbox"
PI_AGENT_BASE_IMAGE="pi-agent-sandbox:base"
PI_AGENT_CURRENT_IMAGE="pi-agent-sandbox:current"
PI_AGENT_ACTIVE_CONTAINER="pi-agent-active"
PI_AGENT_WORKSPACE_ROOT="$HOME/workspace"
PI_AGENT_STATE_DIR="$PI_AGENT_DOCKER_DIR/.state/$PI_AGENT_IMAGE_REPO"
PI_AGENT_LOCK_TIMEOUT="5"
PI_AGENT_SNAPSHOT_KEEP="10"
PI_AGENT_AUTO_PRUNE="1"
PI_AGENT_FLATTEN_LAYER_THRESHOLD="100"
```

`PI_AGENT_STATE_DIR` must be an absolute path and must not contain backslashes.
The installer applies the same rule to its install directory, preventing an
accidental `\\` input from creating a relative directory.

Linux defaults:

```sh
PI_AGENT_DOCKERFILE="Dockerfile.linux"
PI_AGENT_HOST_UID="$(id -u)"
PI_AGENT_HOST_GID="$(id -g)"
PI_AGENT_IMAGE_REPO="pi-agent-sandbox-linux"
PI_AGENT_BASE_IMAGE="pi-agent-sandbox-linux:base"
PI_AGENT_CURRENT_IMAGE="pi-agent-sandbox-linux:current"
PI_AGENT_ACTIVE_CONTAINER="pi-agent-active-linux"
PI_AGENT_FLATTEN_LAYER_THRESHOLD="100"
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
