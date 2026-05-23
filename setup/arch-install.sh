#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#   Interactive Arch Linux installer — for VirtualBox / bare metal
#   Guides you through: partition → format → pacstrap → chroot →
#   user setup → bootloader → reboot → then runs boot.sh
# ═══════════════════════════════════════════════════════════════════
set -eEo pipefail

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
  warn "Not running from Arch ISO. Partitioning will destroy data."
  ask_yn "Continue anyway?" y || fatal "Aborted."
fi

UEFI=false
[[ -d /sys/firmware/efi ]] && UEFI=true

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

# ═══════════════════════════════════════════════════════════════════
#  MODE: Single boot vs Dual boot
# ═══════════════════════════════════════════════════════════════════
echo "  ${C_BOLD}Install mode:${C_RESET}"
echo "    1) Single boot — wipe entire disk, install Arch only"
echo "    2) Dual boot — install alongside Windows (existing ESP)"
echo
read -p "$(printf '%s[?]%s Select [1/2]: ' "$C_YELLOW" "$C_RESET")" INSTALL_MODE

if [[ "$INSTALL_MODE" == "2" ]]; then
  # ═════════════════════════════════════════════════════════════════
  #  DUAL BOOT
  # ═════════════════════════════════════════════════════════════════
  log "Dual-boot mode selected."
  echo
  log "Available partitions:"
  lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT | grep -E 'part|disk' | head -20
  echo

  # Detect ESP
  ESP_PART=""
  for part in $(lsblk -lno NAME /dev/sd* /dev/nvme* 2>/dev/null | grep -E 'sd[a-z][0-9]|nvme[0-9]n[0-9]p[0-9]' | sort -u); do
    blkid "/dev/$part" 2>/dev/null | grep -qi 'EFI\|vfat' && ESP_PART="/dev/$part" && break
  done
  if [[ -z "$ESP_PART" ]]; then
    warn "Could not auto-detect ESP. Enter manually (e.g. nvme0n1p1):"
    ask "EFI system partition: " ESP_INPUT
    ESP_PART="/dev/$ESP_INPUT"
  fi
  ok "ESP found: $ESP_PART"

  # Select Linux root partition
  echo
  log "Select the partition for Linux root (/). It will be FORMATTED."
  ask "Linux root partition (e.g. nvme0n1p2): " ROOT_INPUT
  PART="/dev/$ROOT_INPUT"
  [[ ! -b "$PART" ]] && fatal "Partition $PART not found."

  ask_yn "Format $PART as ext4? ALL DATA on it will be LOST." n || fatal "Aborted."

  # Format root
  log "Formatting $PART as ext4..."
  mkfs.ext4 -F "$PART"
  ok "Formatted."

  # Mount
  log "Mounting..."
  mount "$PART" /mnt
  mkdir -p /mnt/boot
  mount "$ESP_PART" /mnt/boot
  ok "Mounted $PART to /mnt, $ESP_PART to /mnt/boot"

  # Pacstrap — add os-prober + ntfs-3g for Windows detection
  log "Installing base system..."
  pacstrap -K /mnt base base-devel linux linux-firmware \
    sudo grub networkmanager vim git efibootmgr os-prober ntfs-3g
  genfstab -U /mnt >> /mnt/etc/fstab

  CHROOT_DISK=""  # not used in dual boot (GRUB uses --efi-directory)

else
  # ═════════════════════════════════════════════════════════════════
  #  SINGLE BOOT (original flow)
  # ═════════════════════════════════════════════════════════════════
  warn "This will DESTROY all data on the target disk."
  ask_yn "Ready to start?" y || exit 0

  echo
  log "Available disks:"
  lsblk -d -o NAME,SIZE,MODEL | grep -v loop
  echo

  DISK=""
  while [[ -z "$DISK" ]]; do
    ask "Which disk to install on? (e.g. sda, nvme0n1): " DISK
    [[ -b "/dev/$DISK" ]] || { err "Not found."; DISK=""; }
  done
  DISK="/dev/$DISK"
  ask_yn "ERASE ALL DATA on $DISK?" n || fatal "Aborted."

  echo
  log "Partitioning $DISK"
  echo "  ${C_BOLD}Method:${C_RESET}"
  echo "    1) Auto — create partitions and format"
  if $UEFI; then echo "       (UEFI: 512MB FAT32 EFI + ext4 root)"
  else echo "       (BIOS: single ext4 partition)"; fi
  echo "    2) Manual — open fdisk"
  echo "    3) Skip — disk already partitioned"
  read -p "$(printf '%s[?]%s Select [1/2/3]: ' "$C_YELLOW" "$C_RESET")" PART_METHOD

  case "$PART_METHOD" in
    2) fdisk "$DISK" ;;
    3) log "Skipping." ;;
    *)
      if $UEFI; then
        log "Auto UEFI: EFI + root..."
        blkdiscard -f "$DISK" 2>/dev/null || true
        parted -s "$DISK" mklabel gpt
        parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
        parted -s "$DISK" set 1 esp on
        parted -s "$DISK" mkpart primary ext4 513MiB 100%
      else
        log "Auto BIOS: single ext4..."
        blkdiscard -f "$DISK" 2>/dev/null || true
        parted -s "$DISK" mklabel gpt
        parted -s "$DISK" mkpart primary ext4 0% 100%
        parted -s "$DISK" set 1 boot on
      fi
      sleep 1
      ok "Partitions created." ;;
  esac

  detect_part() {
    local d="$1" n="$2"
    echo "$d" | grep -q 'nvme' && echo "${d}p${n}" || echo "${d}${n}"
  }

  if $UEFI; then
    ESP_PART=$(detect_part "$DISK" 1)
    PART=$(detect_part "$DISK" 2)
  else
    PART=$(detect_part "$DISK" 1)
  fi

  # Fallback: scan if partitions not found
  if [[ ! -b "$PART" ]]; then
    warn "Scanning partitions..."
    FOUND=$(lsblk -lno NAME "$DISK" | grep -v "$(basename "$DISK")" | head -1)
    [[ -n "$FOUND" ]] && PART="/dev/$FOUND" || { ask "Enter partition manually: " P; PART="/dev/$P"; }
  fi
  ok "Using: $PART"

  # Format
  if $UEFI; then
    mkfs.fat -F 32 "$ESP_PART"
    log "EFI formatted."
  fi
  mkfs.ext4 -F "$PART"

  # Mount
  mount "$PART" /mnt
  if $UEFI; then
    mkdir -p /mnt/boot
    mount "$ESP_PART" /mnt/boot
  fi
  ok "Mounted."

  # Pacstrap
  log "Installing base system..."
  pacstrap -K /mnt base base-devel linux linux-firmware \
    sudo grub networkmanager vim git efibootmgr
  genfstab -U /mnt >> /mnt/etc/fstab

  if $UEFI; then
    CHROOT_DISK=""  # UEFI: use --efi-directory
  else
    CHROOT_DISK="$DISK"  # BIOS: install to disk MBR
  fi
fi

# ═══════════════════════════════════════════════════════════════════
#  CHROOT SETUP (shared by both modes)
# ═══════════════════════════════════════════════════════════════════
cat > /mnt/setup-chroot.sh <<CHROOTSCRIPT
#!/bin/bash
set -e

HOSTNAME="nier-arch"
USERNAME="archuser"

echo "\$HOSTNAME" > /etc/hostname
echo "127.0.1.1  \$HOSTNAME.localdomain  \$HOSTNAME" >> /etc/hosts

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "Set ROOT password:"
passwd

useradd -m -G wheel -s /bin/bash "\$USERNAME"
echo "Set password for \$USERNAME:"
passwd "\$USERNAME"
echo "\$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/\$USERNAME
chmod 440 /etc/sudoers.d/\$USERNAME

# Bootloader
if ${UEFI}; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
  # Enable os-prober to detect Windows (dual-boot)
  echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
else
  grub-install ${CHROOT_DISK}
fi
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
echo "[✓] Chroot done."
CHROOTSCRIPT

chmod +x /mnt/setup-chroot.sh
log "Configuring system (chroot)..."
arch-chroot /mnt ./setup-chroot.sh
rm -f /mnt/setup-chroot.sh

# ═══════════════════════════════════════════════════════════════════
#  FINISH
# ═══════════════════════════════════════════════════════════════════
echo
ok "${C_BOLD}Installation complete!${C_RESET}"
echo
if [[ "$INSTALL_MODE" == "2" ]]; then
  echo "  ─── Dual boot ───"
  echo "  GRUB installed to existing ESP."
  echo "  Windows should appear in the boot menu."
else
  echo "  ─────────────────────────────────────────────"
  echo "   IMPORTANT: Eject the Arch ISO from"
  echo "   VirtualBox (Devices → Optical Drive →"
  echo "   Remove disk from virtual drive)."
  echo "  ─────────────────────────────────────────────"
fi
echo
echo "  ─────────────────────────────────────────────"
echo "   1. Reboot"
echo "   2. Log in as: archuser"
echo "   3. Run:"
echo "      bash <(curl -fsSL https://raw.githubusercontent.com/"
echo "        fahmiirsyadk/arch/main/boot.sh) --vm"
echo "  ─────────────────────────────────────────────"
echo

if ask_yn "Reboot now?" y; then
  umount -R /mnt 2>/dev/null || true
  reboot
fi