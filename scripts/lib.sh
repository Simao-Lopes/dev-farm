#!/usr/bin/env bash
# lib.sh — shared helpers for all dev-farm bootstrap scripts.
# Source this from the other scripts (do not run directly).
# Only requires: bash 3.2+, curl, and (later) Homebrew.

set -euo pipefail

# ── Colors (no-op when not a tty) ──────────────────────────────────────────────
if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_BOLD=""; C_RESET=""
fi

log()  { printf "${C_GREEN}%s${C_RESET}\n" "==> ${1}"; }
warn() { printf "${C_YELLOW}%s${C_RESET}\n" "!!  ${1}"; }
err()  { printf "${C_RED}%s${C_RESET}\n" "XX  ${1}" >&2; }

# ── Validate we are on macOS (all pods are Macs) ──────────────────────────────
require_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    err "This must run on a Mac (pod). Refusing to run on $(uname -s)."
    exit 1
  fi
}

require_root_prompt() {
  # Ensure we can sudo non-interactively for the few sudo steps.
  if ! sudo -n true 2>/dev/null; then
    warn "Some steps need sudo. Enter your password (one prompt, cached for the run)."
    sudo -v
  fi
}

# ── Check a command is on PATH; print a friendly missing-message ──────────────
need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Missing required command: ${cmd}. Install it before continuing."
    return 1
  fi
}

# ── Install Xcode CLT if absent (required by brew + rust + everything) ────────
ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log "Xcode CLT already present at $(xcode-select -p)"
    return 0
  fi
  warn "Installing Xcode Command Line Tools (a GUI prompt will appear — click 'Install')."
  xcode-select --install
  # Wait for install to finish; the user must click Install in the dialog.
  until xcode-select -p >/dev/null 2>&1; do
    sleep 5
    warn "Waiting for Xcode CLT install to complete..."
  done
  log "Xcode CLT installed."
}

# ── Install Homebrew if absent (Apple Silicon prefix /opt/homebrew) ───────────
ensure_brew() {
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew already present: $(command -v brew)"
    return 0
  fi
  warn "Installing Homebrew (non-interactive)."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Enable in this shell (and document reload for future shells).
  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -f /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  log "Homebrew installed."
}

# ── Ensure a Homebrew cask / formula is installed (idempotent) ────────────────
brew_ensure() {
  # brew_ensure <formula|cask --cask foo>
  local spec="$1"
  local name; name="${spec##* }"
  if brew list "$name" >/dev/null 2>&1; then
    log "brew: ${spec} already installed."
  else
    log "brew: installing ${spec} ..."
    brew install "$spec" || brew install --cask "$spec"
  fi
}

# ── Error handle: print and exit, mentioning a resume point ───────────────────
fail() {
  err "${1}"
  warn "You can safely re-run this script — every step is idempotent."
  exit 1
}