# Linux variant for Pi Agent Docker.
# Source this file instead of pi.zsh on native Linux.

_pi_agent_linux_script="${(%):-%N}"
_pi_agent_linux_dir="${_pi_agent_linux_script:A:h}"
source "$_pi_agent_linux_dir/pi.zsh"
unset _pi_agent_linux_script _pi_agent_linux_dir

_pi_agent_linux_uid() { id -u; }
_pi_agent_linux_gid() { id -g; }

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
}
