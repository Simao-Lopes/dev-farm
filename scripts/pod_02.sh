#!/usr/bin/env bash
# pod_02.sh — iOS BUILD/TEST WORKER.
#
#   ~/dev-farm/scripts/pod_02.sh
#
# Assumes comms are already established (01-comms.sh ran on all 3 pods).
# Installs the iOS toolchain so this Mac can build + test a pulled ref:
#   • Xcode Command Line Tools (+ signs-in-ready for Xcode app if needed)
#   • an iOS Simulator runtime
#   • the iOS worker agent (loops pod_00's coordinator on :8411)
#
# NOTE: the full Xcode *app* (GUI, for signing/TestFlight/provisioning) is
# a separate ~12GB App Store install and requires your Apple ID. This script
# installs the CLT + simulators headlessly; do the Xcode app + signing via
# the App Store / Xcode GUI when you need to run on a physical device.
#
# Idempotent — safe to re-run.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_macos

if [ "$(cat "$HOME/.devfarm/pod_name" 2>/dev/null || echo unknown)" != "pod_02" ]; then
  warn "This script targets the pod_02 (iOS worker) Mac. Refusing to continue."
  exit 1
fi

ensure_xcode_clt
ensure_brew

# ── Full Xcode app (needed for signing / TestFlight / physical devices) ───────
if ! xcodebuild -version >/dev/null 2>&1; then
  warn "Xcode (full app) not installed. For SIMULATOR-only builds, CLT is enough;"
  warn "for signing/TestFlight you must install Xcode from the App Store and open it once."
  # Try headless install if xcodegen/mas available; otherwise just instruct.
  if command -v xcodebuild >/dev/null 2>&1; then
    log "xcodebuild is available."
  else
    warn "xcodebuild not found. Install Xcode from the App Store, then re-run."
  fi
fi
log "xcodebuild: $(xcodebuild -version 2>/dev/null | head -1 || echo 'not installed (CLT-only mode)')"

# ── iOS Simulator runtime (headless) ──────────────────────────────────────────
log "Ensuring an iOS Simulator runtime is available."
# 'xcrun simctl runtime list' shows available runtimes.
if command -v xcrun >/dev/null 2>&1 && xcrun simctl runtime list 2>/dev/null | grep -q "iOS"; then
  log "iOS simulator runtime already present."
else
  warn "No iOS simulator runtime. Install one via Xcode → Settings → Components,"
  warn "or run:  xcrun simctl runtime add <your-downloaded-iOS-runtime.dmg>"
  warn "(This step needs the full Xcode app; CLT-only can't download runtimes headlessly.)"
fi

# ── iOS worker agent (loops pod_00's coordinator on :8411) ────────────────────
log "Installing iOS worker agent."
mkdir -p "$HOME/devfarm-worker"
cat > "$HOME/devfarm-worker/ios_worker.py" <<PYEOF
#!/usr/bin/env python3
"""pod_02 iOS worker — polls pod_00's coordinator for build/test jobs."""
import json, os, subprocess, time, urllib.request

ORCH = os.environ.get("DEVFARM_ORCH", "pod_00")
PORT = int(os.environ.get("DEVFARM_WORKER_PORT", 8411))
LOOP = float(os.environ.get("DEVFARM_WORKER_POLL", "10"))
WORK = os.path.expanduser("~/devfarm-work")

def log(*a): print(time.strftime("%H:%M:%S"), *a, flush=True)

def main():
    os.makedirs(WORK, exist_ok=True)
    log(f"iOS worker watching http://{ORCH}:8410/jobs every {LOOP}s (report :{PORT})")
    while True:
        try:
            with urllib.request.urlopen(f"http://{ORCH}:8410/jobs", timeout=5) as r:
                job = json.load(r)
            if job and job.get("job_id"):
                run_job(job)
        except Exception:
            time.sleep(LOOP)
        time.sleep(LOOP)

def run_job(job):
    jid = job["job_id"]; ref = job.get("ref", "main"); repo = job.get("repo", "")
    log(f"job {jid}: xcodebuild test ref {ref}")
    proj = os.path.join(WORK, jid)
    subprocess.run(["git", "clone", repo, proj], check=False)
    cmd = ["xcodebuild", "-scheme", job.get("scheme", "App"), "test",
           "-destination", f"platform=iOS Simulator,name={job.get('sim', 'iPhone 15')}"]
    if os.path.isdir(proj):
        p = subprocess.run(cmd, cwd=proj, capture_output=True)
        code, out = p.returncode, p.stdout
    else:
        code, out = 1, b"no project cloned"
    result = {"job_id": jid, "node": "pod_02", "status": "ok" if code == 0 else "fail",
              "log": (out or b"no log").decode(errors="replace")[-2000:]}
    try:
        req = urllib.request.Request(f"http://{ORCH}:8410/result",
                data=json.dumps(result).encode(), headers={"Content-Type": "application/json"},
                method="POST")
        urllib.request.urlopen(req, timeout=5)
    except Exception as e:
        log(f"  could not report: {e}")

if __name__ == "__main__":
    main()
PYEOF
cat > "$HOME/devfarm-worker/run.sh" <<EOF
#!/usr/bin/env bash
cd "\$HOME/devfarm-work" 2>/dev/null || true
exec python3 "\$HOME/devfarm-worker/ios_worker.py"
EOF
chmod +x "$HOME/devfarm-worker/run.sh"

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

cat <<EOF

────────────────────────────────────────────────────────────────────────
  pod_02 (iOS worker) ready.
    • xcodebuild: $(xcodebuild -version 2>/dev/null | head -1 || echo 'CLT-only')
    • Worker: ~/devfarm-worker/ios_worker.py  (reports :8411)
    • Start loop:  ~/devfarm-worker/run.sh
    • keep-awake:  installed

  For signing / TestFlight: install the full Xcode app from the App Store,
  sign in, import your Apple ID + provisioning profiles into Keychain, then
  re-affix via Xcode → Settings → Accounts.

  Run pod_00's coordinator first so this worker has a job source:
      (on pod_00) python3 ~/pod_00/coordinator.py
────────────────────────────────────────────────────────────────────────
EOF