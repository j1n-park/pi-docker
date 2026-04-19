#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
install_dir="${PI_AGENT_DOCKER_DIR:-$HOME/.config/pi-agent-docker}"
mkdir -p "$install_dir"
cp "$script_dir/Dockerfile" "$script_dir/pi.zsh" "$install_dir/"
cat <<EOF2
Installed Pi Agent Docker wrapper in $install_dir

Add this to your shell config:

  source "$install_dir/pi.zsh"
EOF2
