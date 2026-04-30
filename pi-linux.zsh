# Linux variant for Pi Agent Docker.
# Source this file instead of pi.zsh on native Linux.

_pi_agent_linux_script="${(%):-%N}"
_pi_agent_linux_dir="${_pi_agent_linux_script:A:h}"
source "$_pi_agent_linux_dir/pi.zsh"
unset _pi_agent_linux_script _pi_agent_linux_dir

_pi_agent_linux_uid() {
  id -u
}

_pi_agent_linux_gid() {
  id -g
}

_pi_agent_config() {
  : "${PI_AGENT_DOCKER_DIR:=$HOME/.config/pi-agent-docker}"
  : "${PI_AGENT_DOCKERFILE:=Dockerfile.linux}"
  : "${PI_AGENT_HOST_UID:=$(_pi_agent_linux_uid)}"
  : "${PI_AGENT_HOST_GID:=$(_pi_agent_linux_gid)}"
  : "${PI_AGENT_IMAGE_REPO:=pi-agent-sandbox-linux}"
  : "${PI_AGENT_BASE_IMAGE:=${PI_AGENT_IMAGE_REPO}:base}"
  : "${PI_AGENT_CURRENT_IMAGE:=${PI_AGENT_IMAGE_REPO}:current}"
  : "${PI_AGENT_ACTIVE_CONTAINER:=pi-agent-active-linux}"
  : "${PI_AGENT_SNAPSHOT_KEEP:=10}"
  : "${PI_AGENT_AUTO_PRUNE:=1}"
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
    print -u2 "pi-agent-docker: set PI_AGENT_DOCKER_DIR or install the Linux variant there"
    return 1
  fi

  (( verbose )) && _pi_agent_info "building base image: $PI_AGENT_BASE_IMAGE from $PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE with uid=$PI_AGENT_HOST_UID gid=$PI_AGENT_HOST_GID"
  docker build \
    -f "$PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE" \
    --build-arg "AGENT_UID=$PI_AGENT_HOST_UID" \
    --build-arg "AGENT_GID=$PI_AGENT_HOST_GID" \
    -t "$PI_AGENT_BASE_IMAGE" \
    "$PI_AGENT_DOCKER_DIR"
}

_pi_agent_snapshot_tag() {
  _pi_agent_config
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  print -r -- "${PI_AGENT_IMAGE_REPO}:snap-$stamp"
}

_pi_agent_snapshot_pattern() {
  _pi_agent_config
  print -r -- "^${PI_AGENT_IMAGE_REPO}:snap-[0-9]{8}-[0-9]{6}$"
}

_pi_agent_snapshot_example() {
  _pi_agent_config
  print -r -- "${PI_AGENT_IMAGE_REPO}:snap-YYYYMMDD-HHMMSS"
}

pi-rebuild-base() {
  _pi_agent_extract_verbose "$@"
  if (( _PI_AGENT_HELP )); then
    _pi_agent_usage pi-rebuild-base
    return 0
  fi
  _pi_agent_config
  _pi_agent_require_docker || return $?

  if [[ ! -f "$PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE" ]]; then
    print -u2 "pi-agent-docker: missing Dockerfile at $PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE"
    return 1
  fi

  (( _PI_AGENT_VERBOSE )) && _pi_agent_info "rebuilding base image: $PI_AGENT_BASE_IMAGE from $PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE with uid=$PI_AGENT_HOST_UID gid=$PI_AGENT_HOST_GID"
  docker build \
    -f "$PI_AGENT_DOCKER_DIR/$PI_AGENT_DOCKERFILE" \
    --build-arg "AGENT_UID=$PI_AGENT_HOST_UID" \
    --build-arg "AGENT_GID=$PI_AGENT_HOST_GID" \
    -t "$PI_AGENT_BASE_IMAGE" \
    "$PI_AGENT_DOCKER_DIR"
}
