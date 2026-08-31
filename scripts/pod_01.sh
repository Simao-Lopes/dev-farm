#!/usr/bin/env bash
# pod_01.sh — ANDROID BUILD/TEST WORKER.
#
#   ~/dev-farm/scripts/pod_01.sh
#
# Assumes comms are already established (01-comms.sh ran on all 3 pods).
# Installs the Android toolchain so this Mac can build + test a pulled ref:
#   • Android command-line tools + SDK
#   • a build platform + build-tools (so `./gradlew assembleDebug` works)
#   • accepts SDK licenses
#   • ANDROID_HOME / PATH env in ~/.zshrc
#
# NOTE: an AVD emulator and the Android Studio GUI are optional (gradle
# unit tests need neither). Install them manually if you need emulators.
#
# Idempotent — safe to re-run.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_macos

if [ "$(cat "$HOME/.devfarm/pod_name" 2>/dev/null || echo unknown)" != "pod_01" ]; then
  warn "This script targets the pod_01 (Android worker) Mac. Refusing to continue."
  exit 1
fi

ensure_xcode_clt   # Java/Android needs CLT present
ensure_brew

# ── Java (needed by Gradle) ───────────────────────────────────────────────────
brew_ensure openjdk@17
# Make java available on PATH (brew openjdk is keg-only).
if ! command -v java >/dev/null 2>&1 || [ "$(java -version 2>&1 | head -1)" = "" ]; then
  export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
  if ! grep -q 'openjdk@17/bin' "$HOME/.zshrc" 2>/dev/null; then
    echo 'export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"' >> "$HOME/.zshrc"
    echo 'export JAVA_HOME="/opt/homebrew/opt/openjdk@17"' >> "$HOME/.zshrc"
  fi
fi
log "java: $(java -version 2>&1 | head -1)"

# ── Android command-line tools ────────────────────────────────────────────────
brew_ensure android-commandlinetools 2>/dev/null || \
  brew_ensure android-platform-tools || true
brew_ensure android-platform-tools || true

# SDK root
ANDROID_HOME="$HOME/Library/Android/sdk"
mkdir -p "$ANDROID_HOME"

# sdkmanager + avdmanager (from cmdline-tools)
SDKMAN="${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMAN" ]; then
  warn "android-commandlinetools installed by brew; locating sdkmanager..."
  SDKMAN="$(brew --prefix android-commandlinetools)/bin/sdkmanager" 
fi
if ! command -v sdkmanager >/dev/null 2>&1; then
  # Ensure cmdline-tools is on PATH (formula links it).
  export PATH="$(brew --prefix android-commandlinetools)/bin:$PATH"
fi

if ! command -v sdkmanager >/dev/null 2>&1; then
  warn "sdkmanager not found on PATH. Add the brew bin dir, then re-run:"
  warn "  export PATH=\"$(brew --prefix android-commandlinetools)/bin:\$PATH\""
  exit 1
fi

log "Installing Android SDK: platform-tools, build-tools, platform android-34."
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0" >/dev/null 2>&1 || \
  warn "sdkmanager install of some packages failed (check internet / licenses)."

# ── Set ANDROID_HOME + PATH persistently ──────────────────────────────────────
if ! grep -q 'ANDROID_HOME' "$HOME/.zshrc" 2>/dev/null; then
  {
    echo "export ANDROID_HOME=\"$ANDROID_HOME\""
    echo "export PATH=\"\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH\""
  } >> "$HOME/.zshrc"
fi

log "ANDROID_HOME=$ANDROID_HOME"

# ── Keep-awake watchdog ───────────────────────────────────────────────────────
if ! launchctl print "gui/$(id -u)/devfarm.keep-awake" >/dev/null 2>&1; then
  log "Installing keep-awake LaunchAgent."
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$HOME/Library/LaunchAgents/devfarm.keep-awake.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>devfarm.keep-awake</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/caffeinate</string><string>-s</string><string>-d</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
EOF
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/devfarm.keep-awake.plist" || \
    launchctl load "$HOME/Library/LaunchAgents/devfarm.keep-awake.plist" || true
fi

log "Installing Android worker agent (job loop on :8412)."
install_worker_agent() {
  local port="$1"
  local python_bin="${2:-python3}"
  mkdir -p "$HOME/devfarm-worker"
  cat > "$HOME/devfarm-worker/android_worker.py" <<PYEOF
#!/usr/bin/env python3
"""pod_01 Android worker — polls pod_00's coordinator for build jobs."""
import hashlib, http.client, json, os, subprocess, sys, time, urllib.request

ORCH = os.environ.get("DEVFARM_ORCH", "pod_00")
PORT = int(os.environ.get("DEVFARM_WORKER_PORT", $port))
LOOP = float(os.environ.get("DEVFARM_WORKER_POLL", "10"))
WORK = os.path.expanduser("~/devfarm-work")

def log(*a): print(time.strftime("%H:%M:%S"), *a, flush=True)

job_url = f"http://{ORCH}:8410/jobs"   # pull-based; poll for a job

def main():
    os.makedirs(WORK, exist_ok=True)
    log(f"Android worker watching {job_url} every {LOOP}s (port {PORT})")
    while True:
        try:
            with urllib.request.urlopen(job_url, timeout=5) as r:
                job = json.load(r)
            if job and job.get("job_id"):
                run_job(job)
        except Exception as e:
            time.sleep(LOOP)
        time.sleep(LOOP)

def run_job(job):
    jid = job["job_id"]; ref = job.get("ref", "main"); repo = job.get("repo", "")
    log(f"job {jid}: build+test ref {ref}")
    try:
        subprocess.run(["git", "clone", repo, os.path.join(WORK, jid)], check=False)
    except Exception: pass
    # minimal: run gradle unit tests if a project exists
    code = 0; out = b""
    if os.path.isdir(os.path.join(WORK, jid)):
        out = subprocess.run(
            ["./gradlew", "testDebugUnitTest"], cwd=os.path.join(WORK, jid),
            capture_output=True).stdout
        code = subprocess.run(
            ["./gradlew", "testDebugUnitTest"], cwd=os.path.join(WORK, jid),
            capture_output=True).returncode
    result = {"job_id": jid, "node": "pod_01", "status": "ok" if code == 0 else "fail",
              "log": (out or b"no log").decode(errors="replace")[-2000:]}
    try:
        req = urllib.request.Request(
            f"http://{ORCH}:8410/result", data=json.dumps(result).encode(),
            headers={"Content-Type": "application/json"}, method="POST")
        urllib.request.urlopen(req, timeout=5)
    except Exception as e:
        log(f"  could not report: {e}")

if __name__ == "__main__":
    main()
PYEOF
  cat > "$HOME/devfarm-worker/run.sh" <<EOF
#!/usr/bin/env bash
cd "\$HOME/devfarm-work" 2>/dev/null || true
exec $python_bin "\$HOME/devfarm-worker/android_worker.py"
EOF
  chmod +x "$HOME/devfarm-worker/run.sh"
}
install_worker_agent 8412

cat <<EOF

────────────────────────────────────────────────────────────────────────
  pod_01 (Android worker) ready.
    • Java:   openjdk@17  ($(java -version 2>&1 | head -1))
    • SDK:    \$ANDROID_HOME = $ANDROID_HOME
    • Worker: ~/devfarm-worker/android_worker.py  (loops :8412)
    • Start loop:  ~/devfarm-worker/run.sh
    • keep-awake:  installed

  Run pod_00's coordinator first so this worker has a job source:
      (on pod_00) python3 ~/dev-farm/scripts/../pod_00/coordinator.py
────────────────────────────────────────────────────────────────────────
EOF