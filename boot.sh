#!/bin/bash
set -eEo pipefail

# ─── Banner ────────────────────────────────────────────────────────
clear
cat <<'BANNER'
  ██████  ██    ██  ███    ██ ██ ████████
  ██   ██ ██    ██  ████   ██ ██    ██
  ██████  ██    ██  ██ ██  ██ ██    ██
  ██   ██ ██    ██  ██  ██ ██ ██    ██
  ██   ██  ██████   ██   ████ ██    ██
  ═══════════════════════════════════════
  Arch Linux + Hyprland + Quickshell
  NieR:Automata rice — by fahmiirsyadk
BANNER
echo

# ─── Config ─────────────────────────────────────────────────────────
ARCH_BRANCH="${ARCH_BRANCH:-main}"
ARCH_REPO="${ARCH_REPO:-fahmiirsyadk/arch}"
ARCH_RAW="https://raw.githubusercontent.com/$ARCH_REPO/$ARCH_BRANCH"
ARCH_DEST="$HOME/.local/share/arch"

# ─── Live ISO check — offer interactive installer ─────────────────
if [[ -d /run/archiso ]] || [[ -f /etc/archiso ]] || \
   grep -q 'archiso' /proc/cmdline 2>/dev/null || \
   grep -q '/run/archiso' /proc/mounts 2>/dev/null; then
  # Either on live ISO OR very low disk space
  echo "[!] You are running from the Arch Linux live ISO."
  echo "    The system is not installed yet."
  echo
  echo "    Choose:"
  echo "      1) Full interactive install (partition → pacstrap → chroot → reboot)"
  echo "      2) Exit — I'll install manually first"
  echo
  read -p "Select [1/2]: " CHOICE
  if [[ "$CHOICE" != "2" ]]; then
    echo -e "\n[*] Launching interactive installer..."
    # Fetch and run the interactive installer script
    bash <(curl -fsSL "$ARCH_RAW/setup/arch-install.sh")
    exit 0
  fi
  echo "Exiting. Install Arch manually, then run boot.sh again."
  exit 0
fi

# ─── Root check — create user if running as root ───────────────────
if (( EUID == 0 )); then
  echo "Running as root. Creating a desktop user..."

  DEFAULT_USER="archuser"
  read -p "Username for desktop [archuser]: " DESKTOP_USER
  DESKTOP_USER="${DESKTOP_USER:-$DEFAULT_USER}"

  if ! id "$DESKTOP_USER" &>/dev/null; then
    useradd -m -G wheel -s /bin/bash "$DESKTOP_USER"
    echo "Set password for $DESKTOP_USER:"
    passwd "$DESKTOP_USER"
    echo "$DESKTOP_USER ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/"$DESKTOP_USER"
    chmod 440 /etc/sudoers.d/"$DESKTOP_USER"
    echo "User $DESKTOP_USER created with passwordless sudo."
  fi

  # Save this script to /tmp and re-exec as the new user
  SELF="/tmp/boot-arch.sh"
  curl -fsSL "$ARCH_RAW/boot.sh" -o "$SELF"
  chmod +x "$SELF"
  echo -e "\nRe-running as $DESKTOP_USER..."
  exec sudo -u "$DESKTOP_USER" bash "$SELF" "$@"
fi

# ─── Prepare system ────────────────────────────────────────────────
echo "[*] Seeding mirrorlist..."
if ! sudo test -s /etc/pacman.d/mirrorlist; then
  echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist >/dev/null
fi

echo "[*] Updating system and installing git..."
if [[ $(df --output=avail / | tail -1) -lt 500000 ]]; then
  echo "[!] Very low disk space (<500MB). Skipping system upgrade."
  sudo pacman -S --noconfirm --needed git
else
  sudo pacman -Syu --noconfirm --needed git
fi

# ─── Clone repo ────────────────────────────────────────────────────
echo -e "\n[*] Cloning $ARCH_REPO ($ARCH_BRANCH)..."
rm -rf "$ARCH_DEST"
git clone --depth=1 --branch "$ARCH_BRANCH" "https://github.com/$ARCH_REPO.git" "$ARCH_DEST"

echo "[*] Fixing permissions..."
for f in "$ARCH_DEST"/*.sh; do chmod +x "$f"; done
find "$ARCH_DEST/install" -name '*.sh' -exec chmod +x {} +
find "$ARCH_DEST/lib" -name '*.sh' -exec chmod +x {} +

# ─── Run install ───────────────────────────────────────────────────
echo -e "\n[*] Starting install...\n"
cd "$ARCH_DEST"
source "$ARCH_DEST/install.sh" "$@"