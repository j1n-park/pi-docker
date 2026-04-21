# Linux variant for Pi Agent Docker.
source "${0:A:h}/pi.zsh"

_pi_agent_config() {
  : "${PI_AGENT_DOCKER_DIR:=$HOME/.config/pi-agent-docker}"
  : "${PI_AGENT_DOCKERFILE:=Dockerfile.linux}"
  : "${PI_AGENT_HOST_UID:=$(id -u)}"
  : "${PI_AGENT_HOST_GID:=$(id -g)}"
  : "${PI_AGENT_IMAGE_REPO:=pi-agent-sandbox-linux}"
  : "${PI_AGENT_BASE_IMAGE:=${PI_AGENT_IMAGE_REPO}:base}"
  : "${PI_AGENT_CURRENT_IMAGE:=${PI_AGENT_IMAGE_REPO}:current}"
  : "${PI_AGENT_ACTIVE_CONTAINER:=pi-agent-active-linux}"
}
