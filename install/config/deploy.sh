#!/bin/bash

# ─── Deploy configs ─────────────────────────────────────────────────
deploy_configs() {
  local backup_dir="$ARCH_BACKUP_DIR"

  for name in $ARCH_MANAGED_DIRS; do
    local src="$ARCH_PATH/config/$name"
    local dest="$ARCH_CONFIG_HOME/$name"
    [[ -d "$src" ]] || { warn "Skipping $name (not in repo)."; continue; }

    if [[ -e "$dest" ]]; then
      if $BACKUP_OLD; then
        mkdir -p "$backup_dir/$name"
        log "Backing up $dest → $backup_dir/$name"
        mv "$dest" "$backup_dir/$name"
      else
        warn "Removing existing $dest (no backup)."
        rm -rf "$dest"
      fi
    fi
    cp -r "$src" "$dest"
    ok "Installed config: $name"
  done

  log "Setting executable bits…"
  find "$ARCH_CONFIG_HOME/hypr" "$ARCH_CONFIG_HOME/quickshell" "$ARCH_CONFIG_HOME/waybar" \
    -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + 2>/dev/null || true
}

# ─── user.conf template ────────────────────────────────────────────
create_user_conf() {
  local ucf="$ARCH_CONFIG_HOME/hypr/user.conf"
  if [[ ! -f "$ucf" ]]; then
    cat > "$ucf" <<'EOF'
# Personal Hyprland overrides — NEVER overwritten by updates
# Examples:
#   monitor = DP-1, 2560x1440@144, 0x0, 1
#   bind    = SUPER, B, exec, firefox
EOF
    ok "Created empty ~/.config/hypr/user.conf"
  fi
}

# ─── VM GL tweaks ──────────────────────────────────────────────────
apply_vm_tweaks() {
  $VM_GL_TWEAKS || return 0
  local h="$ARCH_CONFIG_HOME/hypr/hyprland.conf"
  local ucs="$ARCH_CONFIG_HOME/hypr/user.conf"

  if [[ -f "$h" ]] && grep -qE '^exec-once = env QT_MEDIA_BACKEND=ffmpeg qs[[:space:]]*$' "$h" 2>/dev/null; then
    sed -i 's|^exec-once = env QT_MEDIA_BACKEND=ffmpeg qs$|exec-once = env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe QT_MEDIA_BACKEND=ffmpeg QT_QPA_PLATFORM=wayland /usr/bin/qs|' "$h"
    ok "Patched Quickshell for software OpenGL."
  fi

  if [[ -f "$ucs" ]] && ! grep -qF "unit3-vm-gl" "$ucs" 2>/dev/null; then
    cat >>"$ucs" <<'VMGL'

# unit3-vm-gl — Kitty software GL (VirtualBox)
unbind = SUPER, T
bind = SUPER, T, exec, env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe KITTY_GPU_DISABLED=1 /usr/bin/kitty
VMGL
    ok "Added Kitty software GL to user.conf."
  fi
}

# ─── PAM ────────────────────────────────────────────────────────────
deploy_pam() {
  local pam_src="$ARCH_PATH/config/system/pam.d"
  [[ ! -d "$pam_src" ]] && return
  log "Installing PAM configs…"
  for f in "$pam_src"/*; do
    [[ -f "$f" ]] || continue
    sudo install -D -m 644 "$f" "/etc/pam.d/$(basename "$f")"
    ok "PAM: /etc/pam.d/$(basename "$f")"
  done
}

# ─── Shell ──────────────────────────────────────────────────────────
deploy_shell() {
  local bashrc_src="$ARCH_PATH/config/bash/.bashrc"
  local bashrc_dest="$HOME/.bashrc"

  [[ -f "$bashrc_src" ]] || { warn "No .bashrc in repo."; return; }

  if [[ -f "$bashrc_dest" ]] && ! grep -q "Unit-3 default .bashrc" "$bashrc_dest"; then
    mkdir -p "$ARCH_BACKUP_DIR"
    cp "$bashrc_dest" "$ARCH_BACKUP_DIR/.bashrc"
  fi
  cp "$bashrc_src" "$bashrc_dest"

  if [[ ! -f "$HOME/.bashrc.local" ]]; then
    cat > "$HOME/.bashrc.local" <<'OVR'
# Personal overrides — never touched by updates.
OVR
  fi
  ok "Bashrc installed."
}

# ─── Wallpapers + dirs ──────────────────────────────────────────────
setup_dirs() {
  mkdir -p "$ARCH_WALLPAPER_DIR" "$ARCH_SCREENSHOT_DIR"
  if $INSTALL_WALLPAPERS && [[ -d "$ARCH_PATH/assets/wallpapers" ]]; then
    cp -n "$ARCH_PATH/assets/wallpapers/"* "$ARCH_WALLPAPER_DIR/" 2>/dev/null || true
    ok "Wallpapers installed."
  fi
}

# ─── Services ───────────────────────────────────────────────────────
enable_services() {
  log "Enabling services…"
  sudo systemctl enable --now NetworkManager.service 2>/dev/null || warn "NetworkManager: skipped."
  sudo systemctl enable --now bluetooth.service 2>/dev/null || warn "Bluetooth: skipped."
  systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || warn "pipewire: skipped."
}

# ─── qshare symlink ────────────────────────────────────────────────
deploy_qshare() {
  local script="$ARCH_CONFIG_HOME/quickshell/scripts/qshare.py"
  local link="$HOME/.local/bin/qshare"
  [[ ! -f "$script" ]] && return
  mkdir -p "$HOME/.local/bin"
  [[ -L "$link" || -e "$link" ]] && rm -f "$link"
  ln -s "$script" "$link"
  ok "qshare symlinked."
}

# ─── Run all ───────────────────────────────────────────────────────
deploy_configs
create_user_conf
apply_vm_tweaks
deploy_pam
deploy_shell
setup_dirs
enable_services
deploy_qshare

ok "All configs deployed."