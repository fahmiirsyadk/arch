#!/bin/bash

log "Installing base packages…"

extra_pkgs=(
  linux-firmware
  iw wpa_supplicant
  bluez bluez-utils
  sof-firmware alsa-firmware
  intel-media-driver libva-utils vulkan-intel
  xdg-mime xdg-desktop-portal
)

helper="sudo pacman"
command -v yay >/dev/null && helper="yay"
command -v paru >/dev/null && helper="paru"

read_pkgs() {
  grep -vE '^\s*(#|$)' "$1"
}

sudo pacman -S --needed --noconfirm $(read_pkgs "$ARCH_PATH/packages/pacman.txt") "${extra_pkgs[@]}"
ok "Pacman packages installed."

if $INSTALL_AUR && [[ -f "$ARCH_PATH/packages/aur.txt" ]]; then
  log "Installing AUR packages…"
  "$helper" -S --needed --noconfirm $(read_pkgs "$ARCH_PATH/packages/aur.txt")
  ok "AUR packages installed."
fi