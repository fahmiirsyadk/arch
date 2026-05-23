#!/bin/bash

log "Installing base-devel + git…"
sudo pacman -S --needed --noconfirm base-devel git
ok "Base deps installed."