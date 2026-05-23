#!/bin/bash

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

source_all() {
  local dir="$1"
  for f in "$dir"/*.sh; do
    [[ -f "$f" ]] || continue
    source "$f"
  done
}