# Pi Agent Docker shell integration.

_pi_agent_config() {
  : "${PI_AGENT_DOCKER_DIR:=$HOME/.config/pi-agent-docker}"
  : "${PI_AGENT_IMAGE:=pi-agent-sandbox:base}"
}

_pi_agent_target_dir() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

pi() {
  _pi_agent_config
  local target
  target="$(_pi_agent_target_dir)" || return $?
  docker build -f "$PI_AGENT_DOCKER_DIR/Dockerfile" -t "$PI_AGENT_IMAGE" "$PI_AGENT_DOCKER_DIR" || return $?
  docker run --rm -it \
    --workdir /workspace \
    --mount "type=bind,src=$target,dst=/workspace" \
    "$PI_AGENT_IMAGE" \
    /bin/bash -lc 'command -v pi >/dev/null 2>&1 || curl -fsSL https://pi.dev/install.sh | sh; exec pi "$@"' pi "$@"
}

pi-shell() {
  _pi_agent_config
  local target
  target="$(_pi_agent_target_dir)" || return $?
  docker run --rm -it \
    --workdir /workspace \
    --mount "type=bind,src=$target,dst=/workspace" \
    "$PI_AGENT_IMAGE" /bin/bash
}
