#!/usr/bin/env bash
# boot.sh — ONE-LINER for a fully blank Mac.
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Simao-Lopes/dev-farm/main/scripts/boot.sh)"
#
# What it does:
#   1. Installs Xcode CLT + Homebrew + git (a blank Mac has almost nothing).
#   2. Clones the dev-farm repo to ~/dev-farm.
#   3. Hands off to `scripts/01-comms.sh` so comms (Tailscale) comes up FIRST,
#      on every pod, before any role-specific suite is installed.
#
# Idempotent: safe to re-run.

set -euo pipefail

log()  { printf "\033[32m==>\033[0m %s\n" "$1"; }
warn() { printf "\033[33m!! \033[0m %s\n" "$1"; }
err()  { printf "\033[31mXX \033[0m %s\n" "$1" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing: $1"; exit 1; }
}

# ── 1. Xcode CLT ──────────────────────────────────────────────────────────────
if xcode-select -p >/dev/null 2>&1; then
  log "Xcode CLT present."
else
  warn "Installing Xcode Command Line Tools (click 'Install' in the dialog)."
  xcode-select --install
  until xcode-select -p >/dev/null 2>&1; do sleep 5; done
  log "Xcode CLT installed."
fi

# ── 2. Homebrew ───────────────────────────────────────────────────────────────
if command -v brew >/dev/null 2>&1; then
  log "Homebrew present."
else
  warn "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
  log "Homebrew installed."
fi

need_cmd git
log "git present."

# ── 3. Clone dev-farm ─────────────────────────────────────────────────────────
if [ -d "$HOME/dev-farm/.git" ]; then
  log "dev-farm repo already at ~/dev-farm; pulling latest."
  git -C "$HOME/dev-farm" pull --ff-only
else
  git clone https://github.com/Simao-Lopes/dev-farm.git "$HOME/dev-farm"
fi

log "Repo ready at ~/dev-farm"

# ── 4. Hand off to comms ──────────────────────────────────────────────────────
cat <<'EOF'

────────────────────────────────────────────────────────────────────────
  NEXT: establish comms FIRST (Tailscale mesh + SSH between the 3 pods).
  Run on THIS Mac, passing its pod name:

      ~/dev-farm/scripts/01-comms.sh pod_00     # or pod_01 / pod_02

  Do 01-comms.sh on ALL THREE pods before installing any role suites.
────────────────────────────────────────────────────────────────────────
EOF