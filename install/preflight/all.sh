#!/bin/bash

source "$ARCH_INSTALL/preflight/guard.sh"
source "$ARCH_INSTALL/preflight/pacman.sh"
if $INSTALL_AUR; then
  source "$ARCH_INSTALL/preflight/yay-bootstrap.sh"
fi