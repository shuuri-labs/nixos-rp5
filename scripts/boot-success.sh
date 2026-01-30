#!/bin/sh
# =============================================================================
# NixOS Boot Success Handler
# =============================================================================
# This script runs on successful NixOS boot to clear the boot attempt counter.
# Called by systemd after graphical-session.target is reached.
# =============================================================================

BOOT_COUNTER="/rocknix/storage/.nixos-boot-attempts"

log() {
    echo "[boot-success] $*"
    logger -t boot-success "$*"
}

# Clear the boot attempt counter
if [ -f "$BOOT_COUNTER" ]; then
    rm -f "$BOOT_COUNTER"
    log "Cleared boot attempt counter - NixOS booted successfully"
else
    log "No boot counter found (already cleared or first boot)"
fi

# Optionally log boot success for debugging
log "NixOS boot completed successfully at $(date)"

exit 0
