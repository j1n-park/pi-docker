# Pi Agent Docker shell integration.

_pi_agent_config() {
  : "${PI_AGENT_DOCKER_DIR:=$HOME/.config/pi-agent-docker}"
  : "${PI_AGENT_BASE_IMAGE:=pi-agent-sandbox:base}"
  : "${PI_AGENT_CURRENT_IMAGE:=pi-agent-sandbox:current}"
}

_pi_agent_target_dir() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

_pi_agent_image_exists() {
  docker image inspect "$1" >/dev/null 2>&1
}

_pi_agent_ensure_current_image() {
  _pi_agent_config
  if ! _pi_agent_image_exists "$PI_AGENT_BASE_IMAGE"; then
    docker build -f "$PI_AGENT_DOCKER_DIR/Dockerfile" -t "$PI_AGENT_BASE_IMAGE" "$PI_AGENT_DOCKER_DIR" || return $?
  fi
  if ! _pi_agent_image_exists "$PI_AGENT_CURRENT_IMAGE"; then
    docker tag "$PI_AGENT_BASE_IMAGE" "$PI_AGENT_CURRENT_IMAGE"
  fi
}

_pi_agent_run() {
  local command="$1"; shift
  _pi_agent_config
  _pi_agent_ensure_current_image || return $?
  local target container status
  target="$(_pi_agent_target_dir)" || return $?
  container="pi-agent-$RANDOM"
  docker create -it --name "$container" \
    --workdir /workspace \
    --mount "type=bind,src=$target,dst=/workspace" \
    "$PI_AGENT_CURRENT_IMAGE" \
    /bin/bash -lc "$command" "$@" >/dev/null || return $?
  docker start --attach --interactive "$container"
  status=$?
  docker commit "$container" "$PI_AGENT_CURRENT_IMAGE" >/dev/null
  docker rm "$container" >/dev/null 2>&1 || true
  return $status
}

pi() {
  _pi_agent_run 'command -v pi >/dev/null 2>&1 || curl -fsSL https://pi.dev/install.sh | sh; exec pi "$@"' pi "$@"
}

pi-shell() {
  _pi_agent_run 'exec /bin/bash -i "$@"' pi-shell "$@"
}
