#!/usr/bin/env bash
# setup/build.sh — local install entry point
# Usage: bash setup/build.sh [--vm] [--pinned] [--no-aur] [--no-wallpapers]
set -eEo pipefail
cd "$(dirname "$(dirname "$0")")" && source install.sh "$@"