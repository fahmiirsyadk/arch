#!/bin/bash

log "Running guard checks…"

if (( EUID == 0 )); then
  fatal "Running as root. Use boot.sh which creates a normal user."
fi

command -v pacman >/dev/null || fatal "Not on Arch Linux (pacman missing)."
command -v sudo >/dev/null || fatal "sudo is required."

sudo -v || fatal "sudo authentication failed."
while true; do sudo -n true; sleep 60; kill -0 $$ 2>/dev/null || exit; done 2>/dev/null &

ok "Guard checks passed."