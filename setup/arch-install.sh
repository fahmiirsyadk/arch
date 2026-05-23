#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#   Interactive Arch Linux installer — for VirtualBox / bare metal
#   Guides you through: partition → format → pacstrap → chroot →
#   user setup → bootloader → reboot → then runs boot.sh
# ═══════════════════════════════════════════════════════════════════
set -eEo pipefail

# ─── Colors ────────────────────────────────────────────────────────
C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'
C_YELLOW=$'\033[0;33m'; C_BLUE=$'\033[0;34m'
C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'

log()   { printf "%s[*]%s %s\n" "$C_BLUE" "$C_RESET" "$*"; }
ok()    { printf "%s[✓]%s %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf "%s[!]%s %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err()   { printf "%s[✗]%s %s\n" "$C_RED" "$C_RESET" "$*" >&2; }
fatal() { err "$*"; exit 1; }
ask()   { read -rp "$(printf '%s[?]%s %s ' "$C_YELLOW" "$C_RESET" "$1")" "$2"; }
ask_yn() {
  local prompt="$1" default="${2:-n}" reply hint="[y/N]"
  [[ "$default" == "y" ]] && hint="[Y/n]"
  while true; do
    read -rp "$(printf '%s[?]%s %s %s ' "$C_YELLOW" "$C_RESET" "$prompt" "$hint")" reply
    reply="${reply:-$default}"
    case "${reply,,}" in y|yes) return 0 ;; n|no) return 1 ;;
      *) warn "Please answer y or n." ;;
    esac
  done
}

# ─── Detect live ISO ──────────────────────────────────────────────
if [[ ! -d /run/archiso ]] && ! mount | grep -q 'overlay on /'; then
  warn "Not running from Arch ISO. Partitioning will destroy data on the target disk."
  ask_yn "Continue anyway?" y || fatal "Aborted."
fi

# ─── Banner ────────────────────────────────────────────────────────
clear
cat <<'BANNER'
  ╔══════════════════════════════════════════════════════════════╗
  ║      Arch Linux Interactive Installer                       ║
  ║      Hyprland + Quickshell + Rice                           ║
  ║      For VirtualBox / Bare Metal                            ║
  ╚══════════════════════════════════════════════════════════════╝
BANNER
echo
warn "This will DESTROY all data on the target disk."
ask_yn "Ready to start?" y || exit 0

# ═══════════════════════════════════════════════════════════════
#  1. SELECT DISK
# ═══════════════════════════════════════════════════════════════
echo
log "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -v loop
echo

DISK=""
while [[ -z "$DISK" ]]; do
  ask "Which disk to install on? (e.g. sda, nvme0n1): " DISK
  if [[ ! -b "/dev/$DISK" ]]; then
    err "Device /dev/$DISK not found."
    DISK=""
  fi
done
DISK="/dev/$DISK"

ask_yn "Are you sure you want to erase ALL data on $DISK?" n || fatal "Aborted."

# ═══════════════════════════════════════════════════════════════
#  2. PARTITION (cfdisk)
# ═══════════════════════════════════════════════════════════════
echo
log "Opening cfdisk to partition $DISK"
echo "  ─ Create a single Linux filesystem partition filling the disk."
echo "  ─ Type: Linux filesystem (ext4)"
echo "  ─ Then: Write → Quit"
echo
ask_yn "Launch cfdisk now?" y || fatal "Aborted."
cfdisk "$DISK"

# Detect partition name
if echo "$DISK" | grep -q 'nvme'; then
  PART="${DISK}p1"
else
  PART="${DISK}1"
fi

if [[ ! -b "$PART" ]]; then
  warn "$PART not found. Trying to detect..."
  PART="$(lsblk -lno NAME "$DISK" | tail -1)"
  [[ -n "$PART" ]] && PART="/dev/$PART"
  if [[ ! -b "$PART" ]]; then
    fatal "Could not detect partition on $DISK"
  fi
fi
ok "Using partition: $PART"

# ═══════════════════════════════════════════════════════════════
#  3. FORMAT
# ═══════════════════════════════════════════════════════════════
log "Formatting $PART as ext4..."
mkfs.ext4 -F "$PART"
ok "Formatted."

# ═══════════════════════════════════════════════════════════════
#  4. MOUNT
# ═══════════════════════════════════════════════════════════════
log "Mounting $PART to /mnt..."
mount "$PART" /mnt
ok "Mounted."

# ═══════════════════════════════════════════════════════════════
#  5. PACSTRAP
# ═══════════════════════════════════════════════════════════════
log "Installing base system (pacstrap)..."
echo "  This may take a few minutes."
pacstrap -K /mnt base base-devel linux linux-firmware \
  sudo grub networkmanager vim git
ok "Base system installed."

# ═══════════════════════════════════════════════════════════════
#  6. FSTAB
# ═══════════════════════════════════════════════════════════════
genfstab -U /mnt >> /mnt/etc/fstab
ok "fstab generated."

# ═══════════════════════════════════════════════════════════════
#  7. CHROOT SETUP
# ═══════════════════════════════════════════════════════════════════
# Write chroot script with the disk path baked in
cat > /mnt/setup-chroot.sh <<CHROOTSCRIPT
#!/bin/bash
set -e

HOSTNAME="nier-arch"
USERNAME="archuser"

# Hostname
echo "\$HOSTNAME" > /etc/hostname
echo "127.0.1.1  \$HOSTNAME.localdomain  \$HOSTNAME" >> /etc/hosts

# Timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Locale
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Root password
echo "Set ROOT password:"
passwd

# Create user
useradd -m -G wheel -s /bin/bash "\$USERNAME"
echo "Set password for \$USERNAME:"
passwd "\$USERNAME"
echo "\$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/\$USERNAME
chmod 440 /etc/sudoers.d/\$USERNAME

# Bootloader
grub-install ${DISK}
grub-mkconfig -o /boot/grub/grub.cfg

# Network
systemctl enable NetworkManager

echo "[✓] Chroot setup complete."
CHROOTSCRIPT

chmod +x /mnt/setup-chroot.sh

log "Entering chroot to configure system..."
arch-chroot /mnt ./setup-chroot.sh

rm -f /mnt/setup-chroot.sh

# ═══════════════════════════════════════════════════════════════
#  8. FINISH
# ═══════════════════════════════════════════════════════════════
echo
ok "${C_BOLD}Arch Linux base installation complete!${C_RESET}"
echo
echo
echo "  ─────────────────────────────────────────────"
echo "   IMPORTANT: Before rebooting, eject/unmount"
echo "   the Arch ISO from VirtualBox (Devices →"
echo "   Optical Drive → Remove disk from virtual"
echo "   drive), or change boot order to HDD first."
echo "  ─────────────────────────────────────────────"
echo
echo "  ─────────────────────────────────────────────"
echo "   1. Reboot:   reboot"
echo "   2. Log in as: archuser  (password you set)"
echo "   3. Run:"
echo "      bash <(curl -fsSL https://raw.githubusercontent.com/"
echo "        fahmiirsyadk/arch/main/boot.sh) --vm"
echo "  ─────────────────────────────────────────────"
echo

if ask_yn "Reboot now?" y; then
  umount -R /mnt 2>/dev/null || true
  reboot
fi