# Pi Agent Docker shell integration.

_pi_agent_config() {
  : "${PI_AGENT_DOCKER_DIR:=$HOME/.config/pi-agent-docker}"
  : "${PI_AGENT_IMAGE_REPO:=pi-agent-sandbox}"
  : "${PI_AGENT_BASE_IMAGE:=${PI_AGENT_IMAGE_REPO}:base}"
  : "${PI_AGENT_CURRENT_IMAGE:=${PI_AGENT_IMAGE_REPO}:current}"
  : "${PI_AGENT_ACTIVE_CONTAINER:=pi-agent-active}"
}

_pi_agent_info() { print -u2 -r -- "pi-agent-docker: $*"; }
_pi_agent_target_dir() { git rev-parse --show-toplevel 2>/dev/null || pwd; }
_pi_agent_image_exists() { docker image inspect "$1" >/dev/null 2>&1; }

_pi_agent_ensure_current_image() {
  _pi_agent_config
  if ! _pi_agent_image_exists "$PI_AGENT_BASE_IMAGE"; then
    docker build -f "$PI_AGENT_DOCKER_DIR/Dockerfile" -t "$PI_AGENT_BASE_IMAGE" "$PI_AGENT_DOCKER_DIR" || return $?
  fi
  _pi_agent_image_exists "$PI_AGENT_CURRENT_IMAGE" || docker tag "$PI_AGENT_BASE_IMAGE" "$PI_AGENT_CURRENT_IMAGE"
}

_pi_agent_workspace() {
  local target="$1" name
  name="${target:t}"
  [[ -z "$name" || "$name" == "/" ]] && name="workspace"
  print -r -- "/workspace/$name"
}

_pi_agent_run() {
  local mode="$1"; shift
  _pi_agent_config
  _pi_agent_ensure_current_image || return $?
  local target workspace snapshot status
  target="$(_pi_agent_target_dir)" || return $?
  workspace="$(_pi_agent_workspace "$target")"
  snapshot="${PI_AGENT_IMAGE_REPO}:snap-$(date +%Y%m%d-%H%M%S)"
  docker tag "$PI_AGENT_CURRENT_IMAGE" "$snapshot" || return $?
  docker create -it --name "$PI_AGENT_ACTIVE_CONTAINER" \
    --workdir "$workspace" \
    --mount "type=bind,src=$target,dst=$workspace" \
    "$PI_AGENT_CURRENT_IMAGE" \
    /bin/bash -lc "$mode" "$@" >/dev/null || return $?
  docker start --attach --interactive "$PI_AGENT_ACTIVE_CONTAINER"
  status=$?
  docker commit --change "LABEL pi.agent.previous_state=$snapshot" "$PI_AGENT_ACTIVE_CONTAINER" "$PI_AGENT_CURRENT_IMAGE" >/dev/null
  docker rm "$PI_AGENT_ACTIVE_CONTAINER" >/dev/null 2>&1 || true
  return $status
}

pi() { _pi_agent_run 'exec pi "$@"' pi "$@"; }
pi-shell() { _pi_agent_run 'exec /bin/bash -i "$@"' pi-shell "$@"; }

pi-status() {
  _pi_agent_config
  print -r -- "PI_AGENT_DOCKER_DIR=$PI_AGENT_DOCKER_DIR"
  print -r -- "PI_AGENT_CURRENT_IMAGE=$PI_AGENT_CURRENT_IMAGE"
  docker images "$PI_AGENT_IMAGE_REPO"
}

pi-snapshots() {
  _pi_agent_config
  docker images "$PI_AGENT_IMAGE_REPO" --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}' | grep ':snap-' | sort -r
}
