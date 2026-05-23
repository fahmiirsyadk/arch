#!/bin/bash

bootstrap_aur_helper() {
  if command -v yay >/dev/null; then ok "yay already installed."; return; fi
  if command -v paru >/dev/null; then ok "paru already installed."; return; fi
  log "Bootstrapping yay (AUR helper)…"
  local d; d=$(mktemp -d)
  git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$d/yay-bin"
  (cd "$d/yay-bin" && makepkg -si --noconfirm)
  rm -rf "$d"
  ok "yay installed."
}

bootstrap_aur_helper