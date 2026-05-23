#!/bin/bash

export REPO_BRANCH="${ARCH_BRANCH:-main}"
export REPO_URL="https://github.com/fahmiirsyadk/arch.git"
export REPO_RAW="https://raw.githubusercontent.com/fahmiirsyadk/arch/$REPO_BRANCH"

export ARCH_PATH_DEFAULT="$HOME/.local/share/arch"
export ARCH_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export ARCH_BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"

export ARCH_MANAGED_DIRS="hypr quickshell waybar kitty dunst"
export ARCH_PRESERVED_FILES="hypr/user.conf quickshell/settings/Settings.qml"

export ARCH_WALLPAPER_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/wallpapers"
export ARCH_SCREENSHOT_DIR="$HOME/Screenshots"

PINNED_MODE=false
VM_GL_TWEAKS=false
INSTALL_AUR=true
INSTALL_WALLPAPERS=true
INSTALL_BASHRC=true
BACKUP_OLD=true

if [[ -n ${ARCH_PATH:-} ]]; then
  export ARCH_PATH
elif [[ -e $ARCH_PATH_DEFAULT ]]; then
  export ARCH_PATH="$ARCH_PATH_DEFAULT"
else
  export ARCH_PATH="$ARCH_PATH_DEFAULT"
fi

case ":$PATH:" in
  *":$ARCH_PATH/bin:"*) ;;
  *) export PATH="$ARCH_PATH/bin:$PATH" ;;
esac