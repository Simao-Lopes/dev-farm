#!/usr/bin/env bash
# 01-comms.sh — ESTABLISH COMMS BETWEEN PODS FIRST.
#
#   ~/dev-farm/scripts/01-comms.sh <pod_00|pod_01|pod_02>
#
# Run THIS on ALL THREE Macs BEFORE installing any Android/iOS suite.
# It brings up:
#   • Tailscale mesh (WireGuard) — every pod on the same tailnet by name
#   • cluster SSH keys — so pod_00 can reach pod_01/pod_02 and vice-versa
#   • a shared "devfarm" ssh alias per pod, pointing at the other two
#
# Idempotent — safe to re-run; each pod must be reachable by name:
#   pod_00  (orchestrator / browser door)
#   pod_01  (Android build/test worker)
#   pod_02  (iOS build/test worker)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_macos

POD_NAME="${1:-}"
if [[ "$POD_NAME" != pod_00 && "$POD_NAME" != pod_01 && "$POD_NAME" != pod_02 ]]; then
  fail "usage: 01-comms.sh <pod_00|pod_01|pod_02>  (got: '${POD_NAME}')"
fi
log "Configuring comms for: ${POD_NAME}"

# The two *other* pods this one must reach (mesh / git).
declare -a PEERS
case "$POD_NAME" in
  pod_00) PEERS=(pod_01 pod_02) ;;
  pod_01) PEERS=(pod_00 pod_02) ;;
  pod_02) PEERS=(pod_00 pod_01) ;;
esac

ensure_xcode_clt
ensure_brew
brew_ensure git
brew_ensure tailscale

# ── 1. Hostname ───────────────────────────────────────────────────────────────
log "Setting macOS hostname to ${POD_NAME} (so it's stable on the tailnet)."
sudo scutil --set HostName   "$POD_NAME"
sudo scutil --set LocalHostName "$POD_NAME"
sudo scutil --set ComputerName  "$POD_NAME"

# ── 2. Tailscale ──────────────────────────────────────────────────────────────
log "Bringing up Tailscale as node '${POD_NAME}'..."
if ! /usr/local/bin/tailscale status >/dev/null 2>&1 \
   && ! tailscale status >/dev/null 2>&1; then
  warn "Tailscale is not logged in. Sign in with the org identity when prompted, then re-run."
  open -a Tailscale
  # Give the human a moment; "100.64.0.0" appears once online.
  until tailscale ip -4 >/dev/null 2>&1; do sleep 3; done
fi

sudo tailscale set --hostname "$POD_NAME" 2>/dev/null \
  || tailscale set --hostname "$POD_NAME" 2>/dev/null \
  || true

tailscale up --ssh 2>/dev/null || \
  sudo tailscale up --ssh 2>/dev/null || true

log "Tailscale status:"
tailscale status 2>/dev/null || true

# ── 3. Cluster SSH keys (passwordless between pods) ───────────────────────────
log "Generating cluster SSH key (if absent)."
if [ ! -f "$HOME/.ssh/devfarm_ed25519" ]; then
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/devfarm_ed25519" -C "devfarm@${POD_NAME}"
fi

log "Public key for ${POD_NAME}:"
cat "$HOME/.ssh/devfarm_ed25519.pub"
warn "Each pod needs every OTHER pod's public key in ~/.ssh/authorized_keys."
warn "Add the 2 keys (printed on the other pods) with:"
warn "  cat >> ~/.ssh/authorized_keys  then paste key  (echo '<key>' >> ~/.ssh/authorized_keys)"

# ── 4. .ssh/config aliases for the pods ───────────────────────────────────────
log "Writing per-pod SSH aliases to ~/.ssh/config."
COLLECT_KEYS=""
for peer in "${PEERS[@]}"; do
  COLLECT_KEYS+="Host ${peer}\n    HostName ${peer}\n    User ${USER}\n    IdentityFile ~/.ssh/devfarm_ed25519\n    IdentitiesOnly yes\n"
done

touch "$HOME/.ssh/config"
mkdir -p "$HOME/.ssh/config.d"
printf "%b" "$COLLECT_KEYS" > "$HOME/.ssh/config.d/devfarm"
# Merge config.d if not already included.
if ! grep -q "Include config.d/\*" "$HOME/.ssh/config" 2>/dev/null; then
  { echo "Include config.d/*"; cat "$HOME/.ssh/config"; } > "$HOME/.ssh/config.new"
  mv "$HOME/.ssh/config.new" "$HOME/.ssh/config"
fi
chmod 700 "$HOME/.ssh/config"

# ── 5. git identity + role anchor (tells pod_00/pod_01/pod_02 scripts) ────────
log "Writing role anchor so role suites know this is ${POD_NAME}."
mkdir -p "$HOME/.devfarm"
printf '%s\n' "$POD_NAME" > "$HOME/.devfarm/pod_name"

log "Done configuring comms for ${POD_NAME}."
cat <<EOF

────────────────────────────────────────────────────────────────────────
  REPEAT this on the OTHER two Macs:
      ~/dev-farm/scripts/01-comms.sh <other-pod>

  Then exchange public keys between all pods (step 3 above) so
  pod_00 can ssh pod_01 and pod_02.

  VERIFY comms are up from pod_00:
      tailscale status                 # all 3 named nodes online
      ssh pod_01 'hostname'            # -> pod_01
      ssh pod_02 'hostname'            # -> pod_02

  Once ALL THREE answer via ssh, comms are established. Only NOW run
  the role suites:
      ~/dev-farm/scripts/pod_00.sh    # orchestrator (+ dispatch)
      ~/dev-farm/scripts/pod_01.sh    # Android worker
      ~/dev-farm/scripts/pod_02.sh    # iOS worker
────────────────────────────────────────────────────────────────────────
EOF