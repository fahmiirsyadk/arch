#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#   Unit-3 build/setup.sh — Arch Linux installation for samyns
#   Machine: Intel i3-1315U, 42GB RAM, Arch Linux (rolling)
#
#   For fresh Arch install: run this AFTER base OS is installed,
#   from the installed system (not the live ISO).
#
#   For just dotfiles on existing Arch: same script, same flow.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────
readonly REPO_URL="https://github.com/samyns/Unit-3.git"
readonly REPO_BRANCH="${UNIT3_BRANCH:-main}"
readonly CLONE_DIR="${TMPDIR:-/tmp}/Unit-3-$$"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
readonly MANAGED_DIRS=(hypr quickshell waybar kitty dunst)
readonly PRESERVED_FILES=("hypr/user.conf" "quickshell/settings/Settings.qml")

PINNED_MODE=false
VM_GL_TWEAKS=false
BOOT_WALLPAPER_VM=false
INSTALL_AUR=true
INSTALL_WALLPAPERS=true
INSTALL_BASHRC=true
ENABLE_SERVICES=true
BACKUP_OLD=true

[[ "${UNIT3_VM:-}" == "1" || "${UNIT3_VM:-}" == "yes" ]] && VM_GL_TWEAKS=true

for arg in "$@"; do
    case "$arg" in
        --pinned) PINNED_MODE=true ;;
        --latest) PINNED_MODE=false ;;
        --vm) VM_GL_TWEAKS=true ;;
        --no-aur) INSTALL_AUR=false ;;
        --no-wallpapers) INSTALL_WALLPAPERS=false ;;
        --no-bashrc) INSTALL_BASHRC=false ;;
        --no-services) ENABLE_SERVICES=false ;;
        --no-backup) BACKUP_OLD=false ;;
        --help|-h)
            cat <<EOF
Usage: build.sh [options]

  --pinned       Install exact tested versions from Arch Archive.
  --latest       Install latest versions (default).
  --vm           VirtualBox / software OpenGL mode (llvmpipe).
  --no-aur       Skip AUR packages (quickshell-git, awww, pamtester).
  --no-wallpapers  Skip wallpaper installation.
  --no-bashrc    Skip .bashrc installation.
  --no-services  Skip service enabling.
  --no-backup    Skip backing up existing configs.

  ENV: UNIT3_VM=1 same effect as --vm.
EOF
            exit 0 ;;
    esac
done

PRESERVED_STASH=""

# ─── Colors & logging ───────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m';   C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[0;33m'; C_BLUE=$'\033[0;34m'
    C_BOLD=$'\033[1m';     C_RESET=$'\033[0m'
else
    C_RED='';C_GREEN='';C_YELLOW='';C_BLUE='';C_BOLD='';C_RESET=''
fi
log()   { printf "%s[*]%s %s\n" "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf "%s[✓]%s %s\n" "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf "%s[!]%s %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err()   { printf "%s[✗]%s %s\n" "$C_RED"    "$C_RESET" "$*" >&2; }
fatal() { err "$*"; exit 1; }

ask_yn() {
    local prompt="$1" default="${2:-n}" reply hint="[y/N]"
    [[ "$default" == "y" ]] && hint="[Y/n]"
    while true; do
        read -rp "$(printf '%s[?]%s %s %s ' "$C_YELLOW" "$C_RESET" "$prompt" "$hint")" reply
        reply="${reply:-$default}"
        case "${reply,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) warn "Please answer y or n." ;;
        esac
    done
}

cleanup() {
    [[ -d "$CLONE_DIR" ]] && rm -rf "$CLONE_DIR"
    [[ -n "$PRESERVED_STASH" && -d "$PRESERVED_STASH" ]] && rm -rf "$PRESERVED_STASH"
}
trap cleanup EXIT

# ─── Pre-flight ─────────────────────────────────────────────────────
preflight() {
    log "Running pre-flight checks…"
    [[ $EUID -ne 0 ]] || fatal "Do not run as root. Run as your normal user; sudo will be invoked when needed."
    command -v pacman >/dev/null || fatal "pacman not found — this script is for Arch Linux only."
    command -v sudo >/dev/null || fatal "sudo is required."
    command -v git >/dev/null || sudo pacman -S --needed --noconfirm git
    log "Requesting sudo password…"
    sudo -v || fatal "sudo authentication failed."
    while true; do sudo -n true; sleep 60; kill -0 $$ 2>/dev/null || exit; done 2>/dev/null &
    log "Checking internet connectivity…"
    ping -c 1 -W 3 archlinux.org >/dev/null 2>&1 || fatal "No internet connection."
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        warn "Running from inside Hyprland — you will need to log out/restart at the end."
    fi
    ok "All checks passed."
}

# ─── User prompts ───────────────────────────────────────────────────
collect_choices() {
    echo
    log "I'll ask a few questions before starting."
    echo
    BACKUP_OLD=true;          ask_yn "Backup existing configs to $BACKUP_DIR?" y || BACKUP_OLD=false
    INSTALL_AUR=true;         ask_yn "Install AUR packages (quickshell-git, awww)? Highly recommended." y || INSTALL_AUR=false
    INSTALL_WALLPAPERS=true;  ask_yn "Install default wallpapers to ~/Pictures/wallpapers?" y || INSTALL_WALLPAPERS=false
    INSTALL_BASHRC=true;      ask_yn "Install Unit-3 .bashrc?" y || INSTALL_BASHRC=false
    ENABLE_SERVICES=true;     ask_yn "Enable system services (NetworkManager, pipewire)?" y || ENABLE_SERVICES=false

    if $VM_GL_TWEAKS; then
        log "VM/software-GL mode enabled."
    elif ask_yn "VirtualBox or limited GPU? Apply software OpenGL for Quickshell + Kitty?" n; then
        VM_GL_TWEAKS=true
    fi
    if $VM_GL_TWEAKS && $INSTALL_WALLPAPERS; then
        ask_yn "Apply first wallpaper automatically at Hyprland login (awww)?" y && BOOT_WALLPAPER_VM=true || true
    fi
    echo
}

# ─── Base setup ─────────────────────────────────────────────────────
install_base() {
    log "Installing base-devel + git…"
    sudo pacman -S --needed --noconfirm base-devel git
}

# ─── AUR helper ─────────────────────────────────────────────────────
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

# ─── Clone ──────────────────────────────────────────────────────────
clone_repo() {
    log "Cloning Unit-3 ($REPO_BRANCH)…"
    git clone --depth=1 --branch "$REPO_BRANCH" "$REPO_URL" "$CLONE_DIR"
}

# ─── Packages ───────────────────────────────────────────────────────
read_pkg_list() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    grep -vE '^\s*(#|$)' "$file"
}

install_packages() {
    local pacman_list="$CLONE_DIR/packages/pacman.txt"
    local aur_list="$CLONE_DIR/packages/aur.txt"

    local extra_pkgs=(
        # ── Intel WiFi firmware ──────────────────────────────────────
        linux-firmware
        # ── WiFi backends (NetworkManager uses these internally) ─────
        iw wpa_supplicant
        # ── Bluetooth ─────────────────────────────────────────────────
        bluez bluez-utils
        # ── Intel audio firmware (SST / Sound Open Firmware) ─────────
        sof-firmware alsa-firmware
        # ── Intel GPU / VAAPI (hardware video encode/decode on Wayland) ─
        intel-media-driver libva-utils vulkan-intel
        # ── XDG mime (used by xdg-open, file managers) ───────────────
        xdg-mime xdg-desktop-portal
    )

    if $PINNED_MODE; then
        local pinned_pacman="$CLONE_DIR/packages/pinned-pacman.txt"
        local pinned_aur="$CLONE_DIR/packages/pinned-aur.txt"
        log "Pinned mode: installing exact tested versions from Arch Archive."

        if [[ -f "$pinned_pacman" ]]; then
            log "Installing pinned pacman packages…"
            install_pinned_from_archive "$pinned_pacman"
        fi
        if $INSTALL_AUR && [[ -f "$pinned_aur" ]]; then
            warn "AUR packages cannot be pinned — falling back to latest."
            mapfile -t aur_pkgs < <(grep -vE '^\s*(#|$)' "$aur_list")
            local helper; helper=$(command -v yay || command -v paru)
            "$helper" -S --needed --noconfirm "${aur_pkgs[@]}"
        fi
    else
        local pacman_pkgs aur_pkgs
        mapfile -t pacman_pkgs < <(grep -vE '^\s*(#|$)' "$pacman_list")
        if (( ${#pacman_pkgs[@]} > 0 )); then
            log "Installing ${#pacman_pkgs[@]} pacman packages (latest)…"
            sudo pacman -S --needed --noconfirm "${pacman_pkgs[@]}" "${extra_pkgs[@]}"
        fi
        if $INSTALL_AUR && [[ -f "$aur_list" ]]; then
            mapfile -t aur_pkgs < <(grep -vE '^\s*(#|$)' "$aur_list")
            if (( ${#aur_pkgs[@]} > 0 )); then
                log "Installing ${#aur_pkgs[@]} AUR packages (latest)…"
                local helper; helper=$(command -v yay || command -v paru)
                "$helper" -S --needed --noconfirm "${aur_pkgs[@]}"
            fi
        fi
    fi
}

install_pinned_from_archive() {
    local pinned_file="$1"
    local archive_base="https://archive.archlinux.org/packages"
    local urls=()

    while IFS='=' read -r pkg version; do
        [[ "$pkg" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$pkg" || -z "$version" ]] && continue
        local first="${pkg:0:1}"
        local url="$archive_base/$first/$pkg/$pkg-$version-x86_64.pkg.tar.zst"
        urls+=("$url")
    done < "$pinned_file"

    if (( ${#urls[@]} > 0 )); then
        sudo pacman -U --noconfirm "${urls[@]}"
    fi
}

# ─── Preserve user files ─────────────────────────────────────────────
stash_preserved_files() {
    PRESERVED_STASH=$(mktemp -d)
    local count=0
    for rel in "${PRESERVED_FILES[@]}"; do
        local src="$CONFIG_HOME/$rel"
        if [[ -f "$src" ]]; then
            local stash="$PRESERVED_STASH/$rel"
            mkdir -p "$(dirname "$stash")"
            cp -a "$src" "$stash"
            count=$((count + 1))
        fi
    done
    (( count > 0 )) && ok "Preserved $count user file(s)."
}

restore_preserved_files() {
    [[ -z "$PRESERVED_STASH" || ! -d "$PRESERVED_STASH" ]] && return 0
    for rel in "${PRESERVED_FILES[@]}"; do
        local stash="$PRESERVED_STASH/$rel"
        local dest="$CONFIG_HOME/$rel"
        if [[ -f "$stash" ]]; then
            mkdir -p "$(dirname "$dest")"
            cp -a "$stash" "$dest"
            ok "Restored user file: $rel"
        fi
    done
}

# ─── Deploy configs ─────────────────────────────────────────────────
deploy_configs() {
    mkdir -p "$CONFIG_HOME"
    stash_preserved_files

    for name in "${MANAGED_DIRS[@]}"; do
        local src="$CLONE_DIR/config/$name"
        local dest="$CONFIG_HOME/$name"
        [[ -d "$src" ]] || { warn "Skipping $name (not in repo)."; continue; }

        if [[ -e "$dest" ]]; then
            if $BACKUP_OLD; then
                mkdir -p "$BACKUP_DIR"
                log "Backing up $dest → $BACKUP_DIR/$name"
                mv "$dest" "$BACKUP_DIR/$name"
            else
                warn "Removing existing $dest (no backup)."
                rm -rf "$dest"
            fi
        fi
        log "Installing config: $name"
        cp -r "$src" "$dest"
    done

    restore_preserved_files

    log "Setting executable bits on scripts…"
    find "$CONFIG_HOME/hypr" "$CONFIG_HOME/quickshell" "$CONFIG_HOME/waybar" \
        -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + 2>/dev/null || true

    local user_conf="$CONFIG_HOME/hypr/user.conf"
    if [[ ! -f "$user_conf" ]]; then
        cat > "$user_conf" <<'EOF'
# ═══════════════════════════════════════════════════════════════════
# Personal Hyprland overrides — NEVER overwritten by updates
# ═══════════════════════════════════════════════════════════════════
# Examples:
#   monitor = DP-1, 2560x1440@144, 0x0, 1
#   bind    = SUPER, B, exec, firefox
#   env     = GTK_THEME, Adwaita-dark
EOF
        ok "Created empty user.conf."
    else
        ok "Existing user.conf preserved."
    fi
}

# ─── VM / software GL tweaks ───────────────────────────────────────
apply_vm_software_gl_tweaks_deployed() {
    $VM_GL_TWEAKS || return 0
    local h="$CONFIG_HOME/hypr/hyprland.conf"
    local ucs="$CONFIG_HOME/hypr/user.conf"

    if [[ -f "$h" ]] && grep -qE '^exec-once = env QT_MEDIA_BACKEND=ffmpeg qs[[:space:]]*$' "$h" 2>/dev/null; then
        cp -a "$h" "${h}.bak-vmgl-$(date +%Y%m%d%H%M%S)"
        sed -i 's|^exec-once = env QT_MEDIA_BACKEND=ffmpeg qs$|exec-once = env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe QT_MEDIA_BACKEND=ffmpeg QT_QPA_PLATFORM=wayland QT_WAYLAND_DISABLE_WINDOWDECORATION=1 /usr/bin/qs|' "$h"
        ok "Patched hyprland.conf: Quickshell uses software OpenGL."
    fi

    local mark="# unit3-install-vm-gl"
    if [[ -f "$ucs" ]] && ! grep -qF "$mark" "$ucs" 2>/dev/null; then
        cat >>"$ucs" <<'VMGL'

# unit3-install-vm-gl — Kitty + software GL
unbind = SUPER, T
bind = SUPER, T, exec, env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe KITTY_GPU_DISABLED=1 /usr/bin/kitty
VMGL
        ok "Appended Kitty software-GL binds to user.conf."
    fi

    $BOOT_WALLPAPER_VM || return 0
    local first
    first="$(find "$HOME/Pictures/wallpapers" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort | head -n1)"
    if [[ -z "$first" ]]; then
        warn "No images in ~/Pictures/wallpapers."
        return 0
    fi
    local wb="# unit3-install-boot-wallpaper"
    if [[ -f "$ucs" ]] && grep -qF "$wb" "$ucs" 2>/dev/null; then
        return 0
    fi
    cat >>"$ucs" <<EOF

${wb}
exec-once = sleep 4 && awww img ${first}
EOF
    ok "Added exec-once for wallpaper at login."
}

# ─── PAM / system files ─────────────────────────────────────────────
deploy_system_files() {
    local pam_src="$CLONE_DIR/config/system/pam.d"
    [[ ! -d "$pam_src" ]] && { warn "No system files to install."; return; }
    log "Installing PAM configurations…"
    for f in "$pam_src"/*; do
        [[ -f "$f" ]] || continue
        local name; name=$(basename "$f")
        sudo install -D -m 644 "$f" "/etc/pam.d/$name"
        ok "Installed PAM config: /etc/pam.d/$name"
    done
}

# ─── Shell config ───────────────────────────────────────────────────
deploy_shell_config() {
    $INSTALL_BASHRC || { warn "Skipping .bashrc installation."; return; }

    local bashrc_src="$CLONE_DIR/config/bash/.bashrc"
    local bashrc_dest="$HOME/.bashrc"

    [[ -f "$bashrc_src" ]] || { warn "No bundled .bashrc found."; return; }

    if [[ -f "$bashrc_dest" ]] && ! grep -q "Unit-3 default .bashrc" "$bashrc_dest"; then
        if $BACKUP_OLD; then
            mkdir -p "$BACKUP_DIR"
            cp "$bashrc_dest" "$BACKUP_DIR/.bashrc"
            log "Backed up existing ~/.bashrc"
        fi
    fi

    log "Installing Unit-3 .bashrc…"
    cp "$bashrc_src" "$bashrc_dest"

    if [[ ! -f "$HOME/.bashrc.local" ]]; then
        cat > "$HOME/.bashrc.local" <<'OVR'
# Unit-3 user overrides — never touched by updates.
# Put your aliases, functions, exports here.
OVR
        ok "Created ~/.bashrc.local."
    fi
    ok "Bashrc installed."
}

# ─── User dirs & wallpapers ─────────────────────────────────────────
setup_user_dirs() {
    mkdir -p "$HOME/Pictures/wallpapers" "$HOME/Screenshots"
    if $INSTALL_WALLPAPERS && [[ -d "$CLONE_DIR/assets/wallpapers" ]]; then
        log "Installing default wallpapers…"
        cp -n "$CLONE_DIR/assets/wallpapers/"* "$HOME/Pictures/wallpapers/" 2>/dev/null || true
    fi
}

# ─── Services ───────────────────────────────────────────────────────
enable_services() {
    $ENABLE_SERVICES || { warn "Skipping service activation."; return; }
    log "Enabling system services…"
    sudo systemctl enable --now NetworkManager.service 2>/dev/null || warn "NetworkManager: skipped."
    sudo systemctl enable --now bluetooth.service 2>/dev/null || warn "Bluetooth: skipped."
    log "Enabling user audio services…"
    systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || warn "pipewire: skipped."
}

# ─── qshare symlink ──────────────────────────────────────────────────
deploy_qshare_symlink() {
    local script="$CONFIG_HOME/quickshell/scripts/qshare.py"
    local link="$HOME/.local/bin/qshare"

    [[ ! -f "$script" ]] && { warn "qshare.py not found, skipping symlink."; return; }

    mkdir -p "$HOME/.local/bin"
    [[ -L "$link" || -e "$link" ]] && rm -f "$link"
    ln -s "$script" "$link"
    ok "Symlinked qshare CLI: $link"

    if ! echo "$PATH" | tr ':' '\n' | grep -qFx "$HOME/.local/bin"; then
        warn "~/.local/bin not in PATH. Add to ~/.bashrc.local:"
        warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# ─── Final message ─────────────────────────────────────────────────
finalize() {
    echo
    ok "${C_BOLD}Installation complete!${C_RESET}"
    echo
    echo "  ${C_BOLD}Next steps:${C_RESET}"
    echo "    1. Reboot or log out, then log back into Hyprland."
    echo "    2. Customize via ~/.config/hypr/user.conf"
    echo "    3. Personal bash overrides in ~/.bashrc.local"
    echo "    4. Wallpapers in ~/Pictures/wallpapers/ (SUPER+P to pick)"
    echo "    5. WiFi: nmtui or nmcli; Bluetooth: bluetoothctl"
    if [[ -d "$BACKUP_DIR" ]]; then
        echo
        echo "  ${C_BOLD}Backup:${C_RESET} $BACKUP_DIR"
    fi
    echo
    echo "  ${C_BOLD}Docs:${C_RESET} https://github.com/samyns/Unit-3#readme"
    echo
}

# ─── Main ───────────────────────────────────────────────────────────
main() {
    preflight
    collect_choices
    install_base
    $INSTALL_AUR && bootstrap_aur_helper
    clone_repo
    install_packages
    deploy_configs
    deploy_system_files
    deploy_shell_config
    setup_user_dirs
    apply_vm_software_gl_tweaks_deployed
    deploy_qshare_symlink
    enable_services
    finalize
}

main "$@"