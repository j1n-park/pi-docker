#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./install.sh

Interactively installs Pi Agent Docker wrapper files.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "install.sh: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

default_shell_config() {
  shell_name=$(basename "${SHELL:-}")
  case "$shell_name" in
    zsh)
      printf '%s\n' "$HOME/.zshrc"
      ;;
    bash)
      printf '%s\n' "$HOME/.bashrc"
      ;;
    *)
      printf '%s\n' "$HOME/.zshrc"
      ;;
  esac
}

default_variant() {
  if [ "$(uname -s)" = "Linux" ]; then
    printf '%s\n' "linux"
  else
    printf '%s\n' "mac"
  fi
}

expand_path() {
  path="$1"
  case "$path" in
    "~/"*)
      printf '%s\n' "$HOME/${path#~/}"
      ;;
    "~")
      printf '%s\n' "$HOME"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

append_source_line() {
  config_file="$1"

  if [ -z "$config_file" ]; then
    return 0
  fi

  config_file=$(expand_path "$config_file")

  config_dir=$(dirname -- "$config_file")
  mkdir -p "$config_dir"
  touch "$config_file"

  if grep -F -- "$source_line" "$config_file" >/dev/null 2>&1; then
    echo "Shell config already imports Pi Agent Docker wrapper: $config_file"
    return 0
  fi

  {
    printf '\n'
    printf '# Pi Agent Docker\n'
    printf '%s\n' "$source_line"
  } >>"$config_file"

  echo "Updated shell config: $config_file"
}

if [ ! -t 0 ]; then
  echo "install.sh: interactive terminal required" >&2
  exit 1
fi

variant_default=$(default_variant)
printf 'Variant [mac/linux] [%s]: ' "$variant_default"
IFS= read -r variant || variant=""
if [ -z "$variant" ]; then
  variant="$variant_default"
fi

case "$variant" in
  mac|linux)
    ;;
  *)
    echo "install.sh: invalid variant: $variant" >&2
    exit 2
    ;;
esac

install_dir_default="${PI_AGENT_DOCKER_DIR:-$HOME/.config/pi-agent-docker}"
printf 'Install directory [%s]: ' "$install_dir_default"
IFS= read -r install_dir || install_dir=""
if [ -z "$install_dir" ]; then
  install_dir="$install_dir_default"
fi
install_dir=$(expand_path "$install_dir")

if [ "$variant" = "linux" ]; then
  source_file="pi-linux.zsh"
else
  source_file="pi.zsh"
fi

source_line="source \"$install_dir/$source_file\""

required_files="Dockerfile pi.zsh"
if [ "$variant" = "linux" ]; then
  required_files="$required_files Dockerfile.linux pi-linux.zsh"
fi

for file in $required_files; do
  if [ ! -f "$script_dir/$file" ]; then
    echo "install.sh: missing required file: $script_dir/$file" >&2
    exit 1
  fi
done

mkdir -p "$install_dir"

for file in $required_files; do
  cp "$script_dir/$file" "$install_dir/$file"
done

default_config=$(default_shell_config)
printf 'Shell config file to update [%s]: ' "$default_config"
IFS= read -r shell_config || shell_config=""
if [ -z "$shell_config" ]; then
  shell_config="$default_config"
fi
append_source_line "$shell_config"

cat <<EOF
Installed Pi Agent Docker wrapper.

Variant: $variant
Install dir: $install_dir

Import line:

  $source_line

Reload your shell or run the source command above.
EOF
