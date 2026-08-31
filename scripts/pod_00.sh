#!/usr/bin/env bash
# pod_00.sh — ORCHESTRATOR + BRAIN + BROWSER DOOR.
#
#   ~/dev-farm/scripts/pod_00.sh
#
# Assumes comms are already established (01-comms.sh ran on all 3 pods,
# and pod_00 can `ssh pod_01` / `ssh pod_02`). Installs:
#   • Node.js                       (OpenHands + Claude Code / Codex runtime)
#   • OpenHands browser UI          (the Devin-like door, service :3000)
#   • Claude Code + Codex           (LLM drivers)
#   • a shared git origin           (~/repos/company.git — workers pull by ref)
#   • a keep-awake watchdog         (never sleeps)
#   • a keep-alive worker probe     (pings pod_01/pod_02; alerts if down)
#
# Idempotent — safe to re-run.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_macos

if [ "$(cat "$HOME/.devfarm/pod_name" 2>/dev/null || echo unknown)" != "pod_00" ]; then
  warn "This script targets the pod_00 (orchestrator) Mac. Refusing to continue."
  exit 1
fi

ensure_xcode_clt
ensure_brew

# ── 1. Node.js + tooling ──────────────────────────────────────────────────────
brew_ensure node
brew_ensure jq
brew_ensure colima || true      # container runtime (optional; for OpenHands Docker)
log "node version: $(node --version)"

# ── 2. OpenHands browser door (git clone + npm run) ───────────────────────────
# Lightweight path: clone OpenHands, install deps, run its dev server on :3000.
# (No Docker dependency — keeps it zero-maintenance on a Mac.)
if [ ! -d "$HOME/dev-farm/ghcr-openhands" ]; then
  :
fi
if [ ! -d "$HOME/OpenHands" ]; then
  log "Cloning OpenHands (browser door)."
  git clone --depth=1 https://github.com/All-Hands-AI/OpenHands.git "$HOME/OpenHands"
else
  log "OpenHands already present; updating."
  git -C "$HOME/OpenHands" pull --ff-only || true
fi
if [ ! -d "$HOME/OpenHands/node_modules" ]; then
  log "Installing OpenHands Python backend + JS deps (first run is slow)."
  cd "$HOME/OpenHands"
  python3 -m venv .venv
  "$HOME/OpenHands/.venv/bin/pip" install -r requirements.txt || \
    "$HOME/OpenHands/.venv/bin/pip" install -e ".[all]" || true
  npm install 2>/dev/null || npm ci 2>/dev/null || true
fi

# ── 3. LLM drivers (Claude Code + Codex) ──────────────────────────────────────
log "Installing Claude Code + Codex (LLM brain drivers)."
npm install -g @anthropic-ai/claude-code 2>/dev/null || warn "claude-code install skipped"
npm install -g @openai/codex 2>/dev/null || warn "codex install skipped"

# LLM API key from Keychain (never stored in repo).
if ! security find-generic-password -s devfarm-llm -a "$USER" >/dev/null 2>&1; then
  warn "No LLM key in Keychain yet (service 'devfarm-llm')."
  warn "Store it, then link to the llm.key file:"
  warn "  security add-generic-password -s devfarm-llm -a \"$USER\" -w '<KEY>'"
fi
mkdir -p "$HOME/.devfarm"
# Populate llm.key if the Keychain entry exists.
if security find-generic-password -s devfarm-llm -a "$USER" >/dev/null 2>&1; then
  security find-generic-password -s devfarm-llm -a "$USER" -w > "$HOME/.devfarm/llm.key"
  chmod 600 "$HOME/.devfarm/llm.key"
  log "Linked LLM key from Keychain -> ~/.devfarm/llm.key"
fi

# ── 4. Shared git origin (workers pull by ref over the tailnet) ───────────────
if [ ! -d "$HOME/repos/company.git" ]; then
  log "Creating shared git origin at ~/repos/company.git"
  mkdir -p "$HOME/repos"
  git init --bare "$HOME/repos/company.git"
  cat > "$HOME/repos/company.git/hooks/post-receive" <<'EOF'
#!/usr/bin/env bash
# On every push, this could touch off a coordinator dispatch. Hook left inert v1.
echo "dev-farm: push received" >> /tmp/devfarm-push.log
EOF
  chmod +x "$HOME/repos/company.git/hooks/post-receive"
else
  log "git origin already present at ~/repos/company.git"
fi

# ── 5. Keep-awake watchdog ────────────────────────────────────────────────────
if ! launchctl print "gui/$(id -u)/devfarm.keep-awake" >/dev/null 2>&1; then
  log "Installing keep-awake LaunchAgent."
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$HOME/Library/LaunchAgents/devfarm.keep-awake.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>devfarm.keep-awake</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/caffeinate</string>
    <string>-s</string>
    <string>-d</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
EOF
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/devfarm.keep-awake.plist" || \
    launchctl load "$HOME/Library/LaunchAgents/devfarm.keep-awake.plist" || true
  log "keep-awake installed (prevents system sleep)."
fi

# ── 6. Keep-alive probe of worker pods ────────────────────────────────────────
log "Verifying worker connectivity from pod_00..."
for peer in pod_01 pod_02; do
  if timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=4 "$peer" 'hostname' >/dev/null 2>&1; then
    log "  ${peer}: UP ($(ssh -o BatchMode=yes "$peer" hostname))"
  else
    warn "  ${peer}: UNREACHABLE. Is 01-comms.sh done on it? Public key exchanged?"
  fi
done

cat <<EOF

────────────────────────────────────────────────────────────────────────
  pod_00 (orchestrator) ready.
    • OpenHands door:   run: cd ~/OpenHands && ~/OpenHands/.venv/bin/python -m openhands
                        (or start via the coordinator service in pod_00/coordinator.py)
    • git origin:       ~/repos/company.git  (workers pull by ref)
    • LLM key linked:   ~/.devfarm/llm.key   (from Keychain)
    • Worker probes:    see output above

  NEXT: still on pod_00, start the coordinator service + install the
  OpenHands/worker wiring (see IMPLEMENTATION.md Phase 5), then run the
  Android + iOS suites on the other pods:
      ~/dev-farm/scripts/pod_01.sh     # on pod_01 (Android)
      ~/dev-farm/scripts/pod_02.sh     # on pod_02 (iOS)
────────────────────────────────────────────────────────────────────────
EOF