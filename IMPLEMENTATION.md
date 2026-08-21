# IMPLEMENTATION — phased build guide

> Run phases **in order**. Each phase is independently verifiable. Full bootstrap scripts
> live in `TEMPLATES/`; edit hostnames/paths first.

## Phase 0 — Preconditions (do ONCE, ~1h)
- [ ] Confirm component identities: Apple IDs for iOS signing, Google Play for Android signing.
- [ ] Apple Developer account ($99/yr) active; a team Apple ID for TestFlight.
- [ ] All three Macs on the same admin owner/network so `ssh` between them is possible.
- [ ] Install **Homebrew** and **Tailscale** on all three (see step 1).
- [ ] Decide the tailnet name (e.g. `acme-eng.ts.net`).

## Phase 1 — Tailscale VPN on all 3 (30 min)
1. On each Mac: `brew install --cask tailscale`.
2. Sign in with the company identity: `tailscale up` (or open the app → sign in).
3. On Mac-H: `tailscale up --advertise-tags=tag:harness --accept-routes` and make it exit-node
   if you want internet routing for workers.
4. Name nodes: `harns`, `ios-worker`, `and-worker`.
5. Create an **ACL file** (see `TEMPLATES/tailnet-acl.example.json`): allow
   `harns → ios-worker, and-worker` on ports 22 + 8411/8412; team users → `harns:3000`.
6. Verify: `tailscale status` shows all three; ping each.

## Phase 2 — Mac-H: browser door + brain (90 min)
1. **OpenHands** (browser UI, Devin-like): `brew install node` then run the prebuilt image:
   ```
   docker run -d --name openhands \
     -p 127.0.0.1:3000:3000 \
     -v ~/.openhands:/.openhands \
     ghcr.io/all-hands-ai/openhands:latest
   ```
   *(or run the `openhands` CLI if you prefer no Docker on the harness; OpenHands supports a
   native agent mode too.)*
2. **Claude Code / Codex driver** on Mac-H:
   - `npm install -g @anthropic-ai/claude-code` (or `openai/codex`);
   - put the API key in macOS **Keychain**, export to the agent env: `osascript -e 'get
     secret ...'` or use `security find-generic-password`.
3. **Git origin** on Mac-H (so workers pull by ref):
   ```
   mkdir -p ~/repos && cd ~/repos && git init --bare company.git
   ssh-add -L   # ensure agent forwards this key to workers
   ```
4. **Worker coordinator** on Mac-H (small Python service, port 8410):
   - watches a "pending builds" queue (git-ref based);
   - dispatches to Mac-I/Mac-A; collects `worker-result.json`; calls back into OpenHands loop.
   - boilerplate in `TEMPLATES/coordinator.py` (to be filled).
5. Start a **keep-awake watchdog** (so it never sleeps at 3am): `TEMPLATES/keep-awake.sh`.
6. Verify: open browser → OpenHands logs in; run a trivial "print hello world" task end-to-end.

## Phase 3 — Mac-I: iOS build/test worker (45 min)
1. Xcode + CLI tools: `xcode-select --install`; ensure `xcodebuild` in PATH.
2. Install **iOS Simulator runtimes** (Xcode → Settings → Components) matching your target.
3. Register the company **Apple ID + signing** in Keychain; create provisioning profiles.
4. Install the **worker agent** (repo `TEMPLATES/ios_worker`): a small daemon that on a job
   `git fetch <ref>` → `xcodebuild test -scheme ... -destination 'platform=iOS Simulator,name=...'`
   → writes `worker-result.json` → posts to coordinator.
5. `keep-awake` too.
6. Verify: run the iOS build of a skeleton app on the simulator; confirm result JSON.

## Phase 4 — Mac-A: Android build/test worker (45 min)
1. Install **Android Studio** + SDK + one **AVD emulator**.
2. Register the **debug keystore** (company debug signing) in Keychain/encrypted file.
3. Install the **worker agent** (`TEMPLATES/android_worker`): on a job `git fetch <ref>` →
   build + run `./gradlew testDebugUnitTest` (and optionally start a headless emulator) →
   `worker-result.json` → post to coordinator.
4. `keep-awake`.
5. Verify: build+test a skeleton Android app; confirm JSON.

## Phase 5 — End-to-end wiring (90 min)
1. Connect OpenHands → coordinator: agent's post-task hook calls `:8410/jobs/new
   {ref, platform: both}`.
2. Confirm coordinator fans out to both workers and collects two results.
3. Add **PR auto-open** from the harness (OpenHands or Codex PR action) so the browser shows
   reviewable change.
4. Verify the full happy path: team asks for "add a sign-in screen to the mobile app" →
   agent codes → iPhone + Android both build & test → PR appears in OpenHands.
5. Stress one failure: break a test, confirm agent retries and workers report non-green.

## Phase 6 — Security & ops hardening (60 min, ongoing)
- [ ] Lock ACLs (see SECURITY.md), disable anonymous OpenHands signups.
- [ ] Set OpenHands behind Tailscale identity (OIDC to company Google/Entra if available).
- [ ] Add **alerts** (you already run a WhatsApp/Telegram Hermes bot) for worker-down and
      build-stuck: `TEMPLATES/loop-alert.sh`.
- [ ] Document recovery: "if Mac-I dies, bootstrap a spare with ios_worker + signing import
      (~30 min)". Put it in OPERATIONS.md.
- [ ] Back up signing + repo to a cloud bucket weekly (or keep on another node).

## Phase 7 — Cutover plan (optional, ~1 day)
- [ ] Run in parallel with Devin for 1–2 sprints.
- [ ] Team does a "dogfood sprint": pick 3 real features, make the farm deliver all 3.
- [ ] When green 2 weeks running → cancel Devin, keep this repo as the source of truth.

---

## Verification gate (do after every phase)
Run the checklist and capture output before moving on:
```
tailscale status                    # 3 nodes visible, ACLs allow harns→workers
openhands: /healthz                 # 200 from another node
coordinator: /healthz               # 200
ios-worker:  latest job result      # JSON with pass + artifact
and-worker:  latest job result      # JSON with pass + artifact
```
Only proceed when each phase's gate is green.