# Pi Agent Docker shell integration.
# Source this file from zsh, for example:
#   source "$HOME/.config/pi-agent-docker/pi.zsh"

typeset -ga _PI_AGENT_CLEARED_ENV=(
  GITHUB_TOKEN
  GH_TOKEN
  SSH_AUTH_SOCK
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN
  GOOGLE_APPLICATION_CREDENTIALS
  KUBECONFIG
  NPM_TOKEN
)
typeset -ga _PI_AGENT_ARGS=()
typeset -gi _PI_AGENT_VERBOSE=0
typeset -gi _PI_AGENT_HELP=0

_pi_agent_config() {
  : "${PI_AGENT_DOCKER_DIR:=$HOME/.config/pi-agent-docker}"
  : "${PI_AGENT_DOCKERFILE:=Dockerfile}"
  : "${PI_AGENT_IMAGE_REPO:=pi-agent-sandbox}"
  : "${PI_AGENT_BASE_IMAGE:=${PI_AGENT_IMAGE_REPO}:base}"
  : "${PI_AGENT_CURRENT_IMAGE:=${PI_AGENT_IMAGE_REPO}:current}"
  : "${PI_AGENT_ACTIVE_CONTAINER:=pi-agent-active}"
  : "${PI_AGENT_WORKSPACE_ROOT:=$HOME/workspace}"
  : "${PI_AGENT_STATE_DIR:=${PI_AGENT_DOCKER_DIR}/.state/${PI_AGENT_IMAGE_REPO}}"
  : "${PI_AGENT_LOCK_TIMEOUT:=5}"
  : "${PI_AGENT_SNAPSHOT_KEEP:=10}"
  : "${PI_AGENT_AUTO_PRUNE:=1}"
  : "${PI_AGENT_FLATTEN_LAYER_THRESHOLD:=100}"
}

_pi_agent_require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    print -u2 "pi-agent-docker: docker is not installed or not on PATH"
    return 127
  fi
}

_pi_agent_info() {
  print -u2 -r -- "pi-agent-docker: $*"
}

_pi_agent_extract_verbose() {
  _PI_AGENT_VERBOSE=0
  _PI_AGENT_HELP=0
  while (( $# )); do
    case "$1" in
      -v|--verbose)
        _PI_AGENT_VERBOSE=1
        shift
        ;;
      -h|--help)
        _PI_AGENT_HELP=1
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done
  _PI_AGENT_ARGS=("$@")
}

_pi_agent_usage() {
  _pi_agent_config
  local command="$1"
  case "$command" in
    pi)
      cat <<EOF
Usage: pi [-v|--verbose] [-h|--help] [--] [args...]

Run Pi in a snapshot-backed Docker container for the current project.

Options:
  -v, --verbose  Print wrapper progress information to stderr.
  -h, --help     Show this help message.
  --             Stop parsing wrapper flags and pass remaining args to Pi.

Helper commands:
  pi-shell         Open an interactive shell in the same environment.
  pi-status        Show configuration, image state, and active container.
  pi-snapshots     List available snapshots.
  pi-rollback      Roll back current image to a snapshot.
  pi-reset-system  Reset current image to the base image.
  pi-reset-all     Remove current image and snapshots.
  pi-rebuild-base  Rebuild the base image from the Dockerfile.
  pi-prune         Remove older snapshots.
  pi-flatten       Flatten the current image to reset Docker layer depth.
  pi-quick-fix     Recover a container left by interrupted sessions.

State:
  current image: $PI_AGENT_CURRENT_IMAGE
  snapshot repo: $PI_AGENT_IMAGE_REPO
  workspace root: $PI_AGENT_WORKSPACE_ROOT
EOF
      ;;
    pi-shell)
      cat <<EOF
Usage: pi-shell [-v|--verbose] [-h|--help] [--] [args...]

Open an interactive shell in the shared snapshot-backed Docker environment.

Options:
  -v, --verbose  Print wrapper progress information to stderr.
  -h, --help     Show this help message.
  --             Stop parsing wrapper flags and pass remaining args to zsh.

State:
  current image: $PI_AGENT_CURRENT_IMAGE
  active container: $PI_AGENT_ACTIVE_CONTAINER
  workspace root: $PI_AGENT_WORKSPACE_ROOT
EOF
      ;;
    pi-status)
      cat <<EOF
Usage: pi-status [-v|--verbose] [-h|--help]

Show wrapper configuration, Docker image state, current image labels, and the
active container for this Pi Agent Docker environment.

Options:
  -v, --verbose  Print extra status collection details to stderr.
  -h, --help     Show this help message.
EOF
      ;;
    pi-snapshots)
      cat <<EOF
Usage: pi-snapshots [-v|--verbose] [-h|--help]

List snapshots for the configured image repo, newest first.

Options:
  -v, --verbose  Print the snapshot count to stderr.
  -h, --help     Show this help message.

Snapshot pattern:
  $(_pi_agent_snapshot_pattern)
EOF
      ;;
    pi-rollback)
      cat <<EOF
Usage: pi-rollback [-v|--verbose] [-h|--help] <snapshot>

Point the current image at a previous snapshot.

Options:
  -v, --verbose  Print rollback details to stderr.
  -h, --help     Show this help message.

Arguments:
  snapshot        Full image tag, or a tag name in $PI_AGENT_IMAGE_REPO.

Example:
  pi-rollback $(_pi_agent_snapshot_example)
EOF
      ;;
    pi-reset-system)
      cat <<EOF
Usage: pi-reset-system [-v|--verbose] [-h|--help]

Reset the current image to the base image. Snapshots are not removed.

Options:
  -v, --verbose  Print reset details to stderr.
  -h, --help     Show this help message.

Images:
  base:    $PI_AGENT_BASE_IMAGE
  current: $PI_AGENT_CURRENT_IMAGE
EOF
      ;;
    pi-reset-all)
      cat <<EOF
Usage: pi-reset-all [-v|--verbose] [-h|--help]

Remove the current image and snapshots for the configured image repo.
The base image is left intact.

Options:
  -v, --verbose  Print each image selected for removal to stderr.
  -h, --help     Show this help message.

Image repo:
  $PI_AGENT_IMAGE_REPO
EOF
      ;;
    pi-rebuild-base)
      cat <<EOF
Usage: pi-rebuild-base [-v|--verbose] [-h|--help]

Rebuild the base image from the configured Dockerfile.

Options:
  -v, --verbose  Print build details to stderr.
  -h, --help     Show this help message.

Build:
  dockerfile: $PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE
  image:      $PI_AGENT_BASE_IMAGE
EOF
      if [[ -n "${PI_AGENT_HOST_UID:-}" && -n "${PI_AGENT_HOST_GID:-}" ]]; then
        cat <<EOF
  uid/gid:    $PI_AGENT_HOST_UID/$PI_AGENT_HOST_GID
EOF
      fi
      ;;
    pi-prune)
      cat <<EOF
Usage: pi-prune [-v|--verbose] [-h|--help] [keep]

Keep only the newest snapshot images and remove older snapshots.

Options:
  -v, --verbose  Print snapshot counts and each removed snapshot to stderr.
  -h, --help     Show this help message.

Arguments:
  keep           Number of newest snapshots to keep.
                 Defaults to PI_AGENT_SNAPSHOT_KEEP=$PI_AGENT_SNAPSHOT_KEEP.
EOF
      ;;
    pi-quick-fix)
      cat <<EOF
Usage: pi-quick-fix [-v|--verbose] [-h|--help]

Recover a shared container left behind after pi or pi-shell sessions were
interrupted. Stale session markers are removed, the previous current image is
snapshotted, the container filesystem is committed to the current image, and
the container is removed.

The persistent lifecycle lock file is acquired but not removed. If an orphaned
container is preventing a lifecycle operation from releasing the lock, an
independent recovery lock is used to commit the container before removing it.
Recovery is refused while a host-side Pi session is still active. If no shared
container exists, there is nothing to recover.

Options:
  -v, --verbose  Print recovery and lock progress to stderr.
  -h, --help     Show this help message.

Lock file:
  $PI_AGENT_STATE_DIR/lifecycle.lock
EOF
      ;;
    pi-flatten)
      cat <<EOF
Usage: pi-flatten [-v|--verbose] [-h|--help]

Flatten the current image to reset Docker layer depth while preserving
container-local filesystem state.

Options:
  -v, --verbose  Print flatten details to stderr.
  -h, --help     Show this help message.

Image:
  current: $PI_AGENT_CURRENT_IMAGE
EOF
      ;;
  esac
}

_pi_agent_target_dir() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" && print -r -- "$root" && return 0
  pwd
}

_pi_agent_prepare_state_dir() {
  _pi_agent_config
  _pi_agent_validate_state_dir || return $?
  mkdir -p "$PI_AGENT_STATE_DIR/sessions" || return $?
}

_pi_agent_validate_state_dir() {
  local state_dir="$PI_AGENT_STATE_DIR"
  if [[ -z "$state_dir" || "$state_dir" != /* || "$state_dir" == *'\\'* ]]; then
    print -u2 "pi-agent-docker: PI_AGENT_STATE_DIR must be an absolute path without backslashes: ${state_dir:-<empty>}"
    return 2
  fi
}

_pi_agent_lock() {
  _pi_agent_prepare_state_dir || return $?
  local lock="$PI_AGENT_STATE_DIR/lifecycle.lock" timeout="$PI_AGENT_LOCK_TIMEOUT"
  if ! [[ "$timeout" == <-> ]]; then
    print -u2 "pi-agent-docker: PI_AGENT_LOCK_TIMEOUT must be a non-negative integer"
    return 2
  fi
  zmodload zsh/system || {
    print -u2 "pi-agent-docker: could not load zsh/system for lifecycle locking"
    return 1
  }
  [[ -e "$lock" ]] || : >"$lock"
  if ! zsystem flock -t "$timeout" -f _PI_AGENT_LOCK_FD "$lock"; then
    _pi_agent_unlock
    print -u2 "pi-agent-docker: timed out after ${timeout}s waiting for lifecycle lock"
    print -u2 "pi-agent-docker: another lifecycle operation is still running; retry after it finishes"
    return 75
  fi
}

_pi_agent_unlock() {
  if [[ -n "${_PI_AGENT_LOCK_FD:-}" ]]; then
    zsystem flock -u "$_PI_AGENT_LOCK_FD" 2>/dev/null || true
    unset _PI_AGENT_LOCK_FD
  fi
}

_pi_agent_session_count() {
  _pi_agent_config
  _pi_agent_validate_state_dir || return $?
  [[ -d "$PI_AGENT_STATE_DIR/sessions" ]] || {
    print -r -- 0
    return 0
  }
  local -a sessions
  sessions=("$PI_AGENT_STATE_DIR"/sessions/*(N))
  print -r -- "${#sessions[@]}"
}

_pi_agent_process_started_at() {
  local pid="$1"
  ps -o lstart= -p "$pid" 2>/dev/null | awk '{$1=$1; print}'
}

_pi_agent_reap_sessions() {
  _pi_agent_config
  local require_launcher="${1:-0}"
  local container="$PI_AGENT_ACTIVE_CONTAINER" session_file session_id launcher_pid launcher_started current_started marker_state query_status
  local -a sessions
  sessions=("$PI_AGENT_STATE_DIR"/sessions/*(N))
  if ! docker container inspect "$container" >/dev/null 2>&1; then
    rm -f "${sessions[@]}"
    return 0
  fi
  for session_file in "${sessions[@]}"; do
    session_id="${session_file:t}"
    launcher_pid="$(awk 'NR == 1 { print $2 }' "$session_file" 2>/dev/null)"
    launcher_started="$(awk 'NR == 1 { $1=$2=""; sub(/^  */, ""); print }' "$session_file" 2>/dev/null)"
    marker_state="$(docker exec "$container" /bin/sh -c '
      session_file="/tmp/pi-agent-sessions/$1"
      if [ ! -r "$session_file" ]; then
        printf absent
        exit 0
      fi
      read -r pid started <"$session_file"
      current="$(awk '\''{ print $22 }'\'' "/proc/$pid/stat" 2>/dev/null)"
      if [ -n "$pid" ] && [ -n "$started" ] && [ "$current" = "$started" ]; then
        printf alive
      else
        printf dead
      fi
    ' sh "$session_id")"
    query_status=$?
    if (( query_status != 0 )); then
      print -u2 "pi-agent-docker: could not verify active session: $session_id"
      return 1
    fi
    case "$marker_state" in
      alive)
        ;;
      absent|dead)
        # A live launcher protects the tiny interval between host registration
        # and the session wrapper writing its container-side marker.
        current_started="$(_pi_agent_process_started_at "$launcher_pid")"
        if [[ "$launcher_pid" == <-> && -n "$launcher_started" && "$current_started" == "$launcher_started" ]]; then
          continue
        fi
        rm -f "$session_file"
        ;;
      *)
        print -u2 "pi-agent-docker: invalid active session marker: $session_id"
        return 1
        ;;
    esac
    if [[ "$marker_state" == "alive" ]] && (( require_launcher )); then
      # pi-quick-fix is specifically for interrupted host sessions. An exec
      # process may survive after its host-side docker client disappears, so
      # require the launcher process to still be the one that registered the
      # session before treating it as active.
      current_started="$(_pi_agent_process_started_at "$launcher_pid")"
      if [[ "$launcher_pid" != <-> || -z "$launcher_started" || "$current_started" != "$launcher_started" ]]; then
        rm -f "$session_file"
      fi
    fi
  done
}

_pi_agent_reap_host_sessions() {
  _pi_agent_config
  local session_file launcher_pid launcher_started current_started
  local -a sessions
  sessions=("$PI_AGENT_STATE_DIR"/sessions/*(N))
  for session_file in "${sessions[@]}"; do
    launcher_pid="$(awk 'NR == 1 { print $2 }' "$session_file" 2>/dev/null)"
    launcher_started="$(awk 'NR == 1 { $1=$2=""; sub(/^  */, ""); print }' "$session_file" 2>/dev/null)"
    current_started="$(_pi_agent_process_started_at "$launcher_pid")"
    if [[ "$launcher_pid" != <-> || -z "$launcher_started" || "$current_started" != "$launcher_started" ]]; then
      rm -f "$session_file"
    fi
  done
}

_pi_agent_workspace_for_target() {
  _pi_agent_config
  local target="$1" root relative
  root="$(cd -P "$PI_AGENT_WORKSPACE_ROOT" 2>/dev/null && pwd)" || {
    print -u2 "pi-agent-docker: workspace root does not exist: $PI_AGENT_WORKSPACE_ROOT"
    return 1
  }
  target="$(cd -P "$target" 2>/dev/null && pwd)" || return $?
  if [[ "$target" == "$root" ]]; then
    print -r -- "/workspace"
    return 0
  fi
  if [[ "$target" != "$root"/* ]]; then
    print -u2 "pi-agent-docker: project is outside PI_AGENT_WORKSPACE_ROOT: $target"
    print -u2 "pi-agent-docker: set PI_AGENT_WORKSPACE_ROOT to a directory containing this project"
    return 1
  fi
  relative="${target#$root/}"
  print -r -- "/workspace/$relative"
}

_pi_agent_container_running() {
  [[ "$(docker container inspect --format '{{.State.Running}}' "$PI_AGENT_ACTIVE_CONTAINER" 2>/dev/null)" == "true" ]]
}

_pi_agent_refuse_while_active() {
  _pi_agent_config
  if docker container inspect "$PI_AGENT_ACTIVE_CONTAINER" >/dev/null 2>&1; then
    print -u2 "pi-agent-docker: shared container is active: $PI_AGENT_ACTIVE_CONTAINER"
    print -u2 "pi-agent-docker: wait for all pi sessions to exit first"
    return 75
  fi
}

_pi_agent_image_exists() {
  docker image inspect "$1" >/dev/null 2>&1
}

_pi_agent_snapshot_pattern() {
  _pi_agent_config
  print -r -- "^${PI_AGENT_IMAGE_REPO}:snap-[0-9]{8}-[0-9]{6}$"
}

_pi_agent_snapshot_example() {
  _pi_agent_config
  print -r -- "${PI_AGENT_IMAGE_REPO}:snap-YYYYMMDD-HHMMSS"
}

_pi_agent_ensure_base_image() {
  _pi_agent_config
  local verbose="${1:-0}"
  if _pi_agent_image_exists "$PI_AGENT_BASE_IMAGE"; then
    (( verbose )) && _pi_agent_info "base image exists: $PI_AGENT_BASE_IMAGE"
    return 0
  fi

  if [[ ! -f "$PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE" ]]; then
    print -u2 "pi-agent-docker: missing Dockerfile at $PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE"
    print -u2 "pi-agent-docker: set PI_AGENT_DOCKER_DIR or install this package there"
    return 1
  fi

  (( verbose )) && _pi_agent_info "building base image: $PI_AGENT_BASE_IMAGE from $PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE"
  docker build -f "$PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE" -t "$PI_AGENT_BASE_IMAGE" "$PI_AGENT_DOCKER_DIR"
}

_pi_agent_ensure_current_image() {
  _pi_agent_config
  local verbose="${1:-0}"
  _pi_agent_ensure_base_image "$verbose" || return $?

  if _pi_agent_image_exists "$PI_AGENT_CURRENT_IMAGE"; then
    (( verbose )) && _pi_agent_info "current image exists: $PI_AGENT_CURRENT_IMAGE"
    return 0
  fi

  (( verbose )) && _pi_agent_info "creating current image from base: $PI_AGENT_BASE_IMAGE -> $PI_AGENT_CURRENT_IMAGE"
  docker tag "$PI_AGENT_BASE_IMAGE" "$PI_AGENT_CURRENT_IMAGE"
}

_pi_agent_snapshot_tag() {
  _pi_agent_config
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  print -r -- "${PI_AGENT_IMAGE_REPO}:snap-$stamp"
}

_pi_agent_create_snapshot() {
  _pi_agent_config
  local verbose="${1:-0}"
  local snapshot
  snapshot="$(_pi_agent_snapshot_tag)"
  while _pi_agent_image_exists "$snapshot"; do
    sleep 1
    snapshot="$(_pi_agent_snapshot_tag)"
  done
  (( verbose )) && _pi_agent_info "creating snapshot from current image: $snapshot"
  docker tag "$PI_AGENT_CURRENT_IMAGE" "$snapshot" || return $?
  (( verbose )) && _pi_agent_info "created snapshot: $snapshot"
  print -r -- "$snapshot"
}

_pi_agent_docker_env_args() {
  local name
  for name in "${_PI_AGENT_CLEARED_ENV[@]}"; do
    print -r -- "--env"
    print -r -- "$name="
  done
}

_pi_agent_import_change_args() {
  local previous_state="${1:-}"
  local committed_at="${2:-}"
  local flattened_at="${3:-}"

  print -r -- "--change"
  print -r -- "ENV HOME=/home/agent"
  print -r -- "--change"
  print -r -- "ENV COLORTERM=truecolor"
  print -r -- "--change"
  print -r -- "ENV PATH=/home/agent/.local/bin:/home/agent/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  print -r -- "--change"
  print -r -- "WORKDIR /workspace"
  print -r -- "--change"
  print -r -- "USER agent"
  print -r -- "--change"
  print -r -- "CMD [\"/bin/zsh\"]"
  if [[ -n "$previous_state" ]]; then
    print -r -- "--change"
    print -r -- "LABEL pi.agent.previous_state=$previous_state"
  fi
  if [[ -n "$committed_at" ]]; then
    print -r -- "--change"
    print -r -- "LABEL pi.agent.committed_at=$committed_at"
  fi
  if [[ -n "$flattened_at" ]]; then
    print -r -- "--change"
    print -r -- "LABEL pi.agent.flattened_at=$flattened_at"
  fi
}

_pi_agent_image_layer_count() {
  docker image inspect "$1" --format '{{len .RootFS.Layers}}' 2>/dev/null
}

_pi_agent_clean_label_value() {
  local value="${1:-}"
  [[ "$value" == "<no value>" ]] && value=""
  print -r -- "$value"
}

_pi_agent_flatten_container_to_current() {
  _pi_agent_config
  local container="$1"
  local previous_state="${2:-}"
  local committed_at="${3:-}"
  local verbose="${4:-0}"
  local flattened_at
  local -a change_args pipe_status

  flattened_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  change_args=("${(@f)$(_pi_agent_import_change_args "$previous_state" "$committed_at" "$flattened_at")}")

  (( verbose )) && _pi_agent_info "flattening container filesystem into current image: $container -> $PI_AGENT_CURRENT_IMAGE"
  docker export "$container" | docker import "${change_args[@]}" - "$PI_AGENT_CURRENT_IMAGE" >/dev/null
  pipe_status=("${pipestatus[@]}")
  if (( pipe_status[1] != 0 || pipe_status[2] != 0 )); then
    print -u2 "pi-agent-docker: docker export/import failed while flattening $container"
    return 1
  fi
  (( verbose )) && _pi_agent_info "flattened current image: $PI_AGENT_CURRENT_IMAGE"
  return 0
}

_pi_agent_flatten_current_image() {
  _pi_agent_config
  local verbose="${1:-0}"
  local temp_container previous_state committed_at flatten_status

  previous_state="$(docker image inspect "$PI_AGENT_CURRENT_IMAGE" --format '{{index .Config.Labels "pi.agent.previous_state"}}' 2>/dev/null)" || previous_state=""
  committed_at="$(docker image inspect "$PI_AGENT_CURRENT_IMAGE" --format '{{index .Config.Labels "pi.agent.committed_at"}}' 2>/dev/null)" || committed_at=""
  previous_state="$(_pi_agent_clean_label_value "$previous_state")"
  committed_at="$(_pi_agent_clean_label_value "$committed_at")"

  temp_container="${PI_AGENT_ACTIVE_CONTAINER}-flatten-$$"
  while docker container inspect "$temp_container" >/dev/null 2>&1; do
    temp_container="${PI_AGENT_ACTIVE_CONTAINER}-flatten-${RANDOM}-$$"
  done

  (( verbose )) && _pi_agent_info "creating temporary flatten container: $temp_container"
  docker create --name "$temp_container" "$PI_AGENT_CURRENT_IMAGE" /bin/true >/dev/null || return $?
  _pi_agent_flatten_container_to_current "$temp_container" "$previous_state" "$committed_at" "$verbose"
  flatten_status=$?
  (( verbose )) && _pi_agent_info "removing temporary flatten container: $temp_container"
  docker rm "$temp_container" >/dev/null 2>&1 || true
  return $flatten_status
}

_pi_agent_maybe_flatten_current_image() {
  _pi_agent_config
  local verbose="${1:-0}"
  local layer_count

  if ! [[ "$PI_AGENT_FLATTEN_LAYER_THRESHOLD" == <-> ]]; then
    print -u2 "pi-agent-docker: flatten layer threshold must be a non-negative integer"
    return 2
  fi
  if (( PI_AGENT_FLATTEN_LAYER_THRESHOLD == 0 )); then
    (( verbose )) && _pi_agent_info "automatic flattening disabled"
    return 0
  fi

  layer_count="$(_pi_agent_image_layer_count "$PI_AGENT_CURRENT_IMAGE")" || return $?
  if ! [[ "$layer_count" == <-> ]]; then
    print -u2 "pi-agent-docker: could not determine layer count for $PI_AGENT_CURRENT_IMAGE"
    return 1
  fi

  if (( layer_count >= PI_AGENT_FLATTEN_LAYER_THRESHOLD )); then
    (( verbose )) && _pi_agent_info "current image has $layer_count layers; flattening at threshold $PI_AGENT_FLATTEN_LAYER_THRESHOLD"
    _pi_agent_flatten_current_image "$verbose"
  else
    (( verbose )) && _pi_agent_info "current image has $layer_count layers; flatten threshold is $PI_AGENT_FLATTEN_LAYER_THRESHOLD"
    return 0
  fi
}

_pi_agent_commit_and_remove() {
  _pi_agent_config
  local container="$1"
  local snapshot="$2"
  local verbose="${3:-0}"
  local committed_at err_file

  committed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if ! err_file="$(mktemp "${TMPDIR:-/tmp}/pi-agent-docker-commit.XXXXXX")"; then
    print -u2 "pi-agent-docker: failed to create temporary commit error file"
    print -u2 "pi-agent-docker: preserving container with uncommitted state: $container"
    return 1
  fi
  (( verbose )) && _pi_agent_info "committing container to current image: $container -> $PI_AGENT_CURRENT_IMAGE"
  docker commit \
    --change "LABEL pi.agent.previous_state=$snapshot" \
    --change "LABEL pi.agent.committed_at=$committed_at" \
    "$container" \
    "$PI_AGENT_CURRENT_IMAGE" >/dev/null 2>"$err_file"
  local commit_status=$?

  if (( commit_status != 0 )); then
    if grep -qi "max depth exceeded" "$err_file"; then
      (( verbose )) && _pi_agent_info "docker commit hit max layer depth; flattening container instead"
      _pi_agent_flatten_container_to_current "$container" "$snapshot" "$committed_at" "$verbose"
      commit_status=$?
      if (( commit_status != 0 )); then
        cat "$err_file" >&2
      fi
    else
      cat "$err_file" >&2
    fi
  fi
  rm -f "$err_file"

  if (( commit_status != 0 )); then
    print -u2 "pi-agent-docker: preserving container with uncommitted state: $container"
    print -u2 "pi-agent-docker: retry after fixing the commit error; do not remove this container"
    return $commit_status
  fi

  # State has been committed successfully. Force removal avoids Docker's
  # graceful-stop timeout for the `sleep infinity` container.
  (( verbose )) && _pi_agent_info "removing shared container: $container"
  if ! docker rm -f "$container" >/dev/null; then
    print -u2 "pi-agent-docker: state was committed, but the shared container could not be removed: $container"
    return 1
  fi
  return 0
}

_pi_agent_report_run_failure() {
  _pi_agent_config
  local container="$1"
  local run_status="$2"

  if docker container inspect "$container" >/dev/null 2>&1; then
    print -u2 "pi-agent-docker: active container already exists: $container"
    print -u2 "pi-agent-docker: inspect it with: docker ps -a --filter name=^/${container}$"
    print -u2 "pi-agent-docker: remove it only if stale: docker rm $container"
  fi
}

_pi_agent_prune_snapshots() {
  _pi_agent_config
  local keep="${1:-$PI_AGENT_SNAPSHOT_KEEP}"
  local verbose="${2:-0}"

  if ! [[ "$keep" == <-> ]]; then
    print -u2 "pi-agent-docker: prune count must be a non-negative integer"
    return 2
  fi

  local snapshot_pattern
  snapshot_pattern="$(_pi_agent_snapshot_pattern)"
  local -a snapshots remove
  snapshots=("${(@f)$(docker images "$PI_AGENT_IMAGE_REPO" --format '{{.Repository}}:{{.Tag}}' \
    | awk -v pattern="$snapshot_pattern" '$1 ~ pattern { print $1 }' \
    | sort -r)}")
  [[ -z "${snapshots[1]:-}" ]] && snapshots=()

  if (( ${#snapshots[@]} <= keep )); then
    if (( verbose )); then
      _pi_agent_info "found ${#snapshots[@]} snapshots; keeping $keep; nothing to prune"
    fi
    return 0
  fi

  remove=("${snapshots[@]:$keep}")
  if (( ${#remove[@]} )); then
    if (( verbose )); then
      _pi_agent_info "removing ${#remove[@]} snapshots; keeping $keep"
      local image
      for image in "${remove[@]}"; do
        _pi_agent_info "removing snapshot: $image"
      done
      docker rmi "${remove[@]}"
    else
      docker rmi "${remove[@]}" >/dev/null
    fi
  fi
}

# Run one interactive command inside the shared container. The wrapper below
# deliberately leaves lifecycle work outside this function so Pi sessions can
# run in parallel.
_pi_agent_exec_session() {
  local mode="$1" workspace="$2" session_id="$3" verbose="$4"
  shift 4
  local -a tty_args
  tty_args=(--interactive)
  [[ -t 0 && -t 1 ]] && tty_args+=(--tty)

  (( verbose )) && _pi_agent_info "opening $mode session in shared container"
  docker exec \
    "${tty_args[@]}" \
    --workdir "$workspace" \
    --env "TERM=${TERM:-xterm-256color}" \
    --env "PI_AGENT_SESSION_ID=$session_id" \
    "$PI_AGENT_ACTIVE_CONTAINER" \
    /bin/bash -lc '
      set -e
      mode="$1"
      shift

      session_file="/tmp/pi-agent-sessions/$PI_AGENT_SESSION_ID"
      mkdir -p /tmp/pi-agent-sessions
      started="$(awk '\''{ print $22 }'\'' "/proc/$$/stat")"
      printf "%s %s\n" "$$" "$started" >"$session_file"
      trap '\''rm -f "$session_file"'\'' EXIT HUP INT TERM

      case "$mode" in
        shell)
          /bin/zsh -i "$@"
          ;;
        pi)
          if ! command -v pi >/dev/null 2>&1; then
            installer="$(mktemp)"
            curl -fsSL https://pi.dev/install.sh -o "$installer"
            if [ -r /dev/tty ]; then sh "$installer" </dev/tty; else sh "$installer"; fi
            rm -f "$installer"
            export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
            hash -r
          fi
          pi "$@"
          ;;
        *)
          echo "pi-agent-docker: unknown session mode: $mode" >&2
          exit 2
          ;;
      esac
    ' pi-session "$mode" "$@"
}

_pi_agent_run() {
  _pi_agent_config
  _pi_agent_require_docker || return $?

  # Keep the lock descriptor scoped to one invocation.  This is deliberately
  # local even though zsystem writes it by parameter name.
  local _PI_AGENT_LOCK_FD
  local mode="$1"
  local verbose="${2:-0}"
  shift 2
  local target container_workspace container session_file session_id run_status commit_status snapshot
  local -a env_args

  target="$(_pi_agent_target_dir)" || return $?
  container_workspace="$(_pi_agent_workspace_for_target "$target")" || return $?
  container="$PI_AGENT_ACTIVE_CONTAINER"

  (( verbose )) && _pi_agent_info "mode: $mode"
  (( verbose )) && _pi_agent_info "host mount target: $target"
  (( verbose )) && _pi_agent_info "container workspace: $container_workspace"
  (( verbose )) && _pi_agent_info "active container name: $PI_AGENT_ACTIVE_CONTAINER"

  # Phase 1: serialize container startup and reserve a session marker.
  # The marker is written before releasing the lock so the last exiting peer
  # cannot commit the container while this session is still starting.
  _pi_agent_lock || return $?
  trap '_pi_agent_unlock; exit 130' HUP INT TERM
  _pi_agent_ensure_current_image "$verbose" || { _pi_agent_unlock; return $?; }
  if docker container inspect "$container" >/dev/null 2>&1 && ! _pi_agent_container_running; then
    print -u2 "pi-agent-docker: shared container is not running: $container"
    print -u2 "pi-agent-docker: remove it after inspecting it: docker rm $container"
    _pi_agent_unlock
    return 75
  fi
  if ! docker container inspect "$container" >/dev/null 2>&1; then
    # Without a container, session markers can only be leftovers from an
    # interrupted earlier generation.
    rm -f "$PI_AGENT_STATE_DIR"/sessions/*(N)
    _pi_agent_maybe_flatten_current_image "$verbose" || { _pi_agent_unlock; return $?; }
    (( verbose )) && _pi_agent_info "starting shared container from image: $PI_AGENT_CURRENT_IMAGE"
    env_args=("${(@f)$(_pi_agent_docker_env_args)}")
    docker run --detach \
      --name "$container" \
      --mount "type=bind,src=$PI_AGENT_WORKSPACE_ROOT,dst=/workspace" \
      "${env_args[@]}" \
      "$PI_AGENT_CURRENT_IMAGE" \
      /bin/sh -c 'exec sleep infinity' >/dev/null || { _pi_agent_unlock; return $?; }
    # The image tag is unchanged until the final session exits, so a snapshot is
    # deliberately created only at that point.
  fi
  session_file="$(mktemp "$PI_AGENT_STATE_DIR/sessions/session.XXXXXX")" || { _pi_agent_unlock; return $?; }
  session_id="${session_file:t}"
  local launcher_pid launcher_started
  # This is the shell running _pi_agent_run, not a command-substitution child
  # that exits before another session can validate this reservation.
  launcher_pid="${ZSH_PID:-$$}"
  launcher_started="$(_pi_agent_process_started_at "$launcher_pid")"
  print -r -- "pending $launcher_pid $launcher_started" >"$session_file"
  _pi_agent_unlock
  trap - HUP INT TERM

  # Phase 2: run Pi or a shell without a global lock.
  _pi_agent_exec_session "$mode" "$container_workspace" "$session_id" "$verbose" "$@"
  run_status=$?

  # Phase 3: the final session snapshots and commits the shared container.
  _pi_agent_lock || return $?
  trap '_pi_agent_unlock; exit 130' HUP INT TERM
  rm -f "$session_file"
  _pi_agent_reap_sessions || { _pi_agent_unlock; return 1; }
  if (( $(_pi_agent_session_count) == 0 )); then
    snapshot="$(_pi_agent_create_snapshot "$verbose")"
    commit_status=$?
    if (( commit_status == 0 )); then
      (( verbose )) && _pi_agent_info "last session exited; committing shared container"
      _pi_agent_commit_and_remove "$container" "$snapshot" "$verbose"
      commit_status=$?
    fi
  else
    (( verbose )) && _pi_agent_info "session exited; shared container remains in use"
    commit_status=0
  fi
  _pi_agent_unlock
  trap - HUP INT TERM

  if (( commit_status == 0 && PI_AGENT_AUTO_PRUNE )); then
    if ! docker container inspect "$container" >/dev/null 2>&1; then
      (( verbose )) && _pi_agent_info "auto-pruning snapshots with keep count: $PI_AGENT_SNAPSHOT_KEEP"
      _pi_agent_prune_snapshots "$PI_AGENT_SNAPSHOT_KEEP" "$verbose" || true
    fi
  elif (( verbose && ! PI_AGENT_AUTO_PRUNE )); then
    _pi_agent_info "auto-prune disabled"
  fi

  if (( commit_status != 0 )); then
    print -u2 "pi-agent-docker: could not finalize shared container: $container"
    print -u2 "pi-agent-docker: inspect the preceding error; recoverable state was not intentionally removed"
    return $commit_status
  fi

  (( verbose )) && _pi_agent_info "returning pi session status: $run_status"
  return $run_status
}

pi() {
  _pi_agent_extract_verbose "$@"
  if (( _PI_AGENT_HELP )); then
    _pi_agent_usage pi
    return 0
  fi
  ( _pi_agent_run pi "$_PI_AGENT_VERBOSE" "${_PI_AGENT_ARGS[@]}" )
}

pi-shell() {
  _pi_agent_extract_verbose "$@"
  if (( _PI_AGENT_HELP )); then
    _pi_agent_usage pi-shell
    return 0
  fi
  ( _pi_agent_run shell "$_PI_AGENT_VERBOSE" "${_PI_AGENT_ARGS[@]}" )
}

pi-status() {
  _pi_agent_extract_verbose "$@"
  if (( _PI_AGENT_HELP )); then
    _pi_agent_usage pi-status
    return 0
  fi
  _pi_agent_config
  _pi_agent_require_docker || return $?

  local target container_workspace
  target="$(_pi_agent_target_dir)" || return $?
  container_workspace="$(_pi_agent_workspace_for_target "$target" 2>/dev/null)" || container_workspace="(outside workspace root)"

  (( _PI_AGENT_VERBOSE )) && _pi_agent_info "collecting status for image repo: $PI_AGENT_IMAGE_REPO"
  (( _PI_AGENT_VERBOSE )) && _pi_agent_info "host mount target resolved to: $target"
  print -r -- "PI_AGENT_DOCKER_DIR=$PI_AGENT_DOCKER_DIR"
  [[ -n "${PI_AGENT_DOCKERFILE:-}" ]] && print -r -- "PI_AGENT_DOCKERFILE=$PI_AGENT_DOCKERFILE"
  [[ -n "${PI_AGENT_HOST_UID:-}" ]] && print -r -- "PI_AGENT_HOST_UID=$PI_AGENT_HOST_UID"
  [[ -n "${PI_AGENT_HOST_GID:-}" ]] && print -r -- "PI_AGENT_HOST_GID=$PI_AGENT_HOST_GID"
  [[ -n "${PI_AGENT_IMAGE_REPO:-}" ]] && print -r -- "PI_AGENT_IMAGE_REPO=$PI_AGENT_IMAGE_REPO"
  print -r -- "PI_AGENT_BASE_IMAGE=$PI_AGENT_BASE_IMAGE"
  print -r -- "PI_AGENT_CURRENT_IMAGE=$PI_AGENT_CURRENT_IMAGE"
  print -r -- "PI_AGENT_ACTIVE_CONTAINER=$PI_AGENT_ACTIVE_CONTAINER"
  print -r -- "PI_AGENT_WORKSPACE_ROOT=$PI_AGENT_WORKSPACE_ROOT"
  print -r -- "PI_AGENT_STATE_DIR=$PI_AGENT_STATE_DIR"
  print -r -- "PI_AGENT_LOCK_TIMEOUT=$PI_AGENT_LOCK_TIMEOUT"
  print -r -- "PI_AGENT_SNAPSHOT_KEEP=$PI_AGENT_SNAPSHOT_KEEP"
  print -r -- "PI_AGENT_AUTO_PRUNE=$PI_AGENT_AUTO_PRUNE"
  print -r -- "PI_AGENT_FLATTEN_LAYER_THRESHOLD=$PI_AGENT_FLATTEN_LAYER_THRESHOLD"
  print -r -- "host mount target=$target"
  print -r -- "container workspace=$container_workspace"
  print -r -- ""
  print -r -- "images:"
  docker images "$PI_AGENT_IMAGE_REPO" --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}'
  print -r -- ""
  print -r -- "current image details:"
  docker image inspect "$PI_AGENT_CURRENT_IMAGE" \
    --format 'id={{.Id}}
created={{.Created}}
layers={{len .RootFS.Layers}}
previous_state={{index .Config.Labels "pi.agent.previous_state"}}
committed_at={{index .Config.Labels "pi.agent.committed_at"}}
flattened_at={{index .Config.Labels "pi.agent.flattened_at"}}' 2>/dev/null \
    || print -r -- "current image is missing"
  print -r -- ""
  print -r -- "active container:"
  docker ps -a --filter "name=^/${PI_AGENT_ACTIVE_CONTAINER}$" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
  print -r -- "active sessions: $(_pi_agent_session_count 2>/dev/null || print 0)"
}

pi-snapshots() {
  _pi_agent_extract_verbose "$@"
  if (( _PI_AGENT_HELP )); then
    _pi_agent_usage pi-snapshots
    return 0
  fi
  _pi_agent_config
  _pi_agent_require_docker || return $?

  local snapshot_pattern
  snapshot_pattern="$(_pi_agent_snapshot_pattern)"
  local -a snapshots
  snapshots=("${(@f)$(docker images "$PI_AGENT_IMAGE_REPO" --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}' \
    | awk -v pattern="$snapshot_pattern" '$1 ~ pattern { print }' \
    | sort -r)}")
  [[ -z "${snapshots[1]:-}" ]] && snapshots=()
  (( _PI_AGENT_VERBOSE )) && _pi_agent_info "found ${#snapshots[@]} snapshots"
  if (( ${#snapshots[@]} )); then
    printf '%s\n' "${snapshots[@]}"
  fi
}

pi-rollback() {
  setopt localoptions localtraps
  _pi_agent_extract_verbose "$@"
  if (( _PI_AGENT_HELP )); then
    _pi_agent_usage pi-rollback
    return 0
  fi
  _pi_agent_config
  _pi_agent_require_docker || return $?
  local _PI_AGENT_LOCK_FD
  _pi_agent_lock || return $?
  trap '_pi_agent_unlock; return 130' HUP INT TERM
  _pi_agent_refuse_while_active || { local status=$?; _pi_agent_unlock; return $status; }

  local snapshot="${_PI_AGENT_ARGS[1]}"
  if [[ -z "$snapshot" ]]; then
    print -u2 "usage: pi-rollback <snapshot>"
    _pi_agent_unlock
    return 2
  fi

  if [[ "$snapshot" != *:* ]]; then
    snapshot="${PI_AGENT_IMAGE_REPO}:$snapshot"
  fi

  if ! _pi_agent_image_exists "$snapshot"; then
    print -u2 "pi-agent-docker: snapshot not found: $snapshot"
    _pi_agent_unlock
    return 1
  fi

  (( _PI_AGENT_VERBOSE )) && _pi_agent_info "rolling back current image to snapshot: $snapshot"
  docker tag "$snapshot" "$PI_AGENT_CURRENT_IMAGE"
  local status=$?
  _pi_agent_unlock
  if (( status == 0 )); then
    (( _PI_AGENT_VERBOSE )) && _pi_agent_info "current image now points to: $snapshot"
  fi
  return $status
}

pi-reset-system() {
  setopt localoptions localtraps
  _pi_agent_extract_verbose "$@"
  if (( _PI_AGENT_HELP )); then
    _pi_agent_usage pi-reset-system
    return 0
  fi
  _pi_agent_config
  _pi_agent_require_docker || return $?
  local _PI_AGENT_LOCK_FD
  _pi_agent_lock || return $?
  trap '_pi_agent_unlock; return 130' HUP INT TERM
  _pi_agent_refuse_while_active || { local status=$?; _pi_agent_unlock; return $status; }
  _pi_agent_ensure_base_image "$_PI_AGENT_VERBOSE" || { local status=$?; _pi_agent_unlock; return $status; }
  (( _PI_AGENT_VERBOSE )) && _pi_agent_info "resetting current image to base: $PI_AGENT_BASE_IMAGE -> $PI_AGENT_CURRENT_IMAGE"
  docker tag "$PI_AGENT_BASE_IMAGE" "$PI_AGENT_CURRENT_IMAGE"
  local status=$?
  _pi_agent_unlock
  if (( status == 0 )); then
    (( _PI_AGENT_VERBOSE )) && _pi_agent_info "current image reset to base"
  fi
  return $status
}

pi-reset-all() {
  setopt localoptions localtraps
  _pi_agent_extract_verbose "$@"
  if (( _PI_AGENT_HELP )); then
    _pi_agent_usage pi-reset-all
    return 0
  fi
  _pi_agent_config
  _pi_agent_require_docker || return $?
  local _PI_AGENT_LOCK_FD
  _pi_agent_lock || return $?
  trap '_pi_agent_unlock; return 130' HUP INT TERM
  _pi_agent_refuse_while_active || { local status=$?; _pi_agent_unlock; return $status; }

  local -a images
  local snapshot_pattern
  snapshot_pattern="$(_pi_agent_snapshot_pattern)"
  images=("${(@f)$(docker images "$PI_AGENT_IMAGE_REPO" --format '{{.Repository}}:{{.Tag}}' \
    | awk -v current="$PI_AGENT_CURRENT_IMAGE" -v pattern="$snapshot_pattern" '$1 == current || $1 ~ pattern { print $1 }')}")
  [[ -z "${images[1]:-}" ]] && images=()

  if (( ${#images[@]} == 0 )); then
    (( _PI_AGENT_VERBOSE )) && _pi_agent_info "no current image or snapshots found to remove"
    _pi_agent_unlock
    return 0
  fi

  if (( _PI_AGENT_VERBOSE )); then
    _pi_agent_info "removing ${#images[@]} images"
    local image
    for image in "${images[@]}"; do
      _pi_agent_info "removing image: $image"
    done
  fi
  docker rmi "${images[@]}"
  local status=$?
  _pi_agent_unlock
  return $status
}

pi-rebuild-base() {
  setopt localoptions localtraps
  _pi_agent_extract_verbose "$@"
  if (( _PI_AGENT_HELP )); then
    _pi_agent_usage pi-rebuild-base
    return 0
  fi
  _pi_agent_config
  _pi_agent_require_docker || return $?
  local _PI_AGENT_LOCK_FD

  if [[ ! -f "$PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE" ]]; then
    print -u2 "pi-agent-docker: missing Dockerfile at $PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE"
    return 1
  fi

  _pi_agent_lock || return $?
  trap '_pi_agent_unlock; return 130' HUP INT TERM
  (( _PI_AGENT_VERBOSE )) && _pi_agent_info "rebuilding base image: $PI_AGENT_BASE_IMAGE from $PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE"
  docker build -f "$PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE" -t "$PI_AGENT_BASE_IMAGE" "$PI_AGENT_DOCKER_DIR"
  local status=$?
  _pi_agent_unlock
  return $status
}

pi-prune() {
  setopt localoptions localtraps
  _pi_agent_extract_verbose "$@"
  if (( _PI_AGENT_HELP )); then
    _pi_agent_usage pi-prune
    return 0
  fi
  _pi_agent_config
  _pi_agent_require_docker || return $?
  local _PI_AGENT_LOCK_FD
  _pi_agent_lock || return $?
  trap '_pi_agent_unlock; return 130' HUP INT TERM
  _pi_agent_refuse_while_active || { local status=$?; _pi_agent_unlock; return $status; }
  _pi_agent_prune_snapshots "${_PI_AGENT_ARGS[1]:-$PI_AGENT_SNAPSHOT_KEEP}" "$_PI_AGENT_VERBOSE"
  local status=$?
  _pi_agent_unlock
  return $status
}

pi-flatten() {
  setopt localoptions localtraps
  _pi_agent_extract_verbose "$@"
  if (( _PI_AGENT_HELP )); then
    _pi_agent_usage pi-flatten
    return 0
  fi
  _pi_agent_config
  _pi_agent_require_docker || return $?
  local _PI_AGENT_LOCK_FD
  _pi_agent_lock || return $?
  trap '_pi_agent_unlock; return 130' HUP INT TERM
  _pi_agent_ensure_current_image "$_PI_AGENT_VERBOSE" || { local status=$?; _pi_agent_unlock; return $status; }
  if docker container inspect "$PI_AGENT_ACTIVE_CONTAINER" >/dev/null 2>&1; then
    _pi_agent_report_run_failure "$PI_AGENT_ACTIVE_CONTAINER" 75
    _pi_agent_unlock
    return 75
  fi
  _pi_agent_flatten_current_image "$_PI_AGENT_VERBOSE"
  local status=$?
  _pi_agent_unlock
  return $status
}

pi-quick-fix() {
  setopt localoptions localtraps
  _pi_agent_extract_verbose "$@"
  if (( _PI_AGENT_HELP )); then
    _pi_agent_usage pi-quick-fix
    return 0
  fi
  _pi_agent_config
  _pi_agent_require_docker || return $?
  _pi_agent_prepare_state_dir || return $?

  zmodload zsh/system || {
    print -u2 "pi-agent-docker: could not load zsh/system for lifecycle locking"
    return 1
  }

  local lock="$PI_AGENT_STATE_DIR/lifecycle.lock"
  [[ -e "$lock" ]] || : >"$lock"
  local _PI_AGENT_LOCK_FD
  local _PI_AGENT_RECOVERY_LOCK_FD
  local recovery_lock="$PI_AGENT_STATE_DIR/recovery.lock"
  local using_recovery_lock=0
  if ! zsystem flock -t 0 -f _PI_AGENT_LOCK_FD "$lock" 2>/dev/null; then
    _pi_agent_unlock

    # Recovery must also work when a failed container exec left a lifecycle
    # operation stuck while holding the lock. Host markers are sufficient to
    # protect live sessions here and do not require access to the container.
    _pi_agent_reap_host_sessions
    local host_session_count
    host_session_count="$(_pi_agent_session_count)" || return $?
    if (( host_session_count != 0 )); then
      print -u2 "pi-agent-docker: shared container still has $host_session_count active host session(s): $PI_AGENT_ACTIVE_CONTAINER"
      print -u2 "pi-agent-docker: wait for active sessions to exit before running pi-quick-fix"
      return 75
    fi

    if docker container inspect "$PI_AGENT_ACTIVE_CONTAINER" >/dev/null 2>&1; then
      # The normal lock owner may itself be blocked on this container. Serialize
      # emergency recoveries separately, then save the filesystem before doing
      # anything that can stop or remove the container.
      [[ -e "$recovery_lock" ]] || : >"$recovery_lock"
      if ! zsystem flock -t 0 -f _PI_AGENT_RECOVERY_LOCK_FD "$recovery_lock" 2>/dev/null; then
        print -u2 "pi-agent-docker: another quick-fix recovery is already running"
        print -u2 "pi-agent-docker: $recovery_lock"
        return 75
      fi
      using_recovery_lock=1
      (( _PI_AGENT_VERBOSE )) && _pi_agent_info "lifecycle lock is busy with no live host session; committing orphaned container before stopping it"
    else
      print -u2 "pi-agent-docker: lifecycle operation is still running; lock is healthy but busy"
      print -u2 "pi-agent-docker: $lock"
      return 75
    fi
  fi

  local container="$PI_AGENT_ACTIVE_CONTAINER"
  local session_count snapshot quick_fix_status=0

  if ! docker container inspect "$container" >/dev/null 2>&1; then
    rm -f "$PI_AGENT_STATE_DIR"/sessions/*(N)
    (( _PI_AGENT_VERBOSE )) && _pi_agent_info "lifecycle lock is healthy and available: $lock"
    (( _PI_AGENT_VERBOSE )) && _pi_agent_info "no shared container needs recovery: $container"
    if (( using_recovery_lock )); then
      zsystem flock -u "$_PI_AGENT_RECOVERY_LOCK_FD" 2>/dev/null || true
    else
      _pi_agent_unlock
    fi
    return 0
  fi

  # Recovery cannot depend on docker exec: an unresponsive exec path is one of
  # the reasons this command is needed. A matching host launcher is the
  # authority for whether a session is still live.
  _pi_agent_reap_host_sessions

  session_count="$(_pi_agent_session_count)" || {
    quick_fix_status=$?
    if (( using_recovery_lock )); then
      zsystem flock -u "$_PI_AGENT_RECOVERY_LOCK_FD" 2>/dev/null || true
    else
      _pi_agent_unlock
    fi
    return $quick_fix_status
  }
  if (( session_count != 0 )); then
    print -u2 "pi-agent-docker: shared container still has $session_count active host session(s): $container"
    print -u2 "pi-agent-docker: wait for active sessions to exit before running pi-quick-fix"
    if (( using_recovery_lock )); then
      zsystem flock -u "$_PI_AGENT_RECOVERY_LOCK_FD" 2>/dev/null || true
    else
      _pi_agent_unlock
    fi
    return 75
  fi

  snapshot="$(_pi_agent_create_snapshot "$_PI_AGENT_VERBOSE")"
  quick_fix_status=$?
  if (( quick_fix_status == 0 )); then
    (( _PI_AGENT_VERBOSE )) && _pi_agent_info "saving and stopping orphaned shared container: $container"
    _pi_agent_commit_and_remove "$container" "$snapshot" "$_PI_AGENT_VERBOSE"
    quick_fix_status=$?
  fi
  if (( using_recovery_lock )); then
    zsystem flock -u "$_PI_AGENT_RECOVERY_LOCK_FD" 2>/dev/null || true
  else
    _pi_agent_unlock
  fi

  if (( quick_fix_status == 0 && PI_AGENT_AUTO_PRUNE )); then
    (( _PI_AGENT_VERBOSE )) && _pi_agent_info "auto-pruning snapshots with keep count: $PI_AGENT_SNAPSHOT_KEEP"
    _pi_agent_prune_snapshots "$PI_AGENT_SNAPSHOT_KEEP" "$_PI_AGENT_VERBOSE" || true
  elif (( _PI_AGENT_VERBOSE && ! PI_AGENT_AUTO_PRUNE )); then
    _pi_agent_info "auto-prune disabled"
  fi

  if (( quick_fix_status != 0 )); then
    print -u2 "pi-agent-docker: could not recover shared container: $container"
    print -u2 "pi-agent-docker: recoverable state was not intentionally removed"
  fi
  return $quick_fix_status
}
