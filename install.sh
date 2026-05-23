#!/bin/bash
set -eEo pipefail

ARCH_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export ARCH_PATH
source "$ARCH_PATH/lib/runtime-env.sh"
export ARCH_INSTALL="$ARCH_PATH/install"

# Parse flags
for arg in "$@"; do
  case "$arg" in
    --pinned) PINNED_MODE=true ;;
    --vm) VM_GL_TWEAKS=true ;;
    --no-aur) INSTALL_AUR=false ;;
    --no-wallpapers) INSTALL_WALLPAPERS=false ;;
    --no-bashrc) INSTALL_BASHRC=false ;;
  esac
done

source "$ARCH_INSTALL/helpers/all.sh"
source "$ARCH_INSTALL/preflight/all.sh"
source "$ARCH_INSTALL/packaging/install.sh"
source "$ARCH_INSTALL/config/deploy.sh"

echo
ok "${C_BOLD}Installation complete!${C_RESET}"
echo
echo "  Next steps:"
echo "    1. Reboot or log out, then log back into Hyprland."
echo "    2. Customize via ~/.config/hypr/user.conf"
echo "    3. Wallpapers in $ARCH_WALLPAPER_DIR (SUPER+P to pick)"
echo "    4. WiFi: nmtui / nmcli; Bluetooth: bluetoothctl"
echo