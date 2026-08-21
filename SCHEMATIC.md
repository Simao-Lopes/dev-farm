# SCHEMATIC — Topology & Ports

## A. Logical topology

```
                            ☁️  LLM providers (Anthropic / OpenRouter)   ← cloud brains
                                        ▲                 │ HTTP/API key
                                        │                 ▼
 ┌──────────────────────────── TAILNET  (tailnet.example.ts.net)  ─────────────────────────────┐
 │                                                                                              │
 │   Mac-H  HARNS  (orchestrator+browser+brain)                                                 │
 │   ├── OpenHands web UI ............ :3000  (browser, team)                                   │
 │   ├── Claude Code / Codex ......... local TTY agent                                          │
 │   ├── git bare/origin + worktrees . :22   (ssh)                                              │
 │   ├── worker coordinator .......... :8410 (HTTP job API)                                     │
 │   └── Tailscale host + ACL ........ node "harns"                                              │
 │                                                                                              │
 │   Mac-I  IOS  (iOS build/test worker)                                                        │
 │   ├── Xcode + iOS Simulator ....... local                                                   │
 │   ├── worker agent ................ :8411 (pulls ref, builds, tests, reports)                │
 │   ├── signing certs (Keychain) .... protected                                                  │
 │   └── Tailscale node "ios-worker"                                                             │
 │                                                                                              │
 │   Mac-A  AND  (Android build/test worker)                                                    │
 │   ├── Android Studio / Gradle/AVD . local                                                    │
 │   ├── worker agent ................ :8412 (pulls ref, builds, tests, reports)                │
 │   ├── signing keystore ............. protected                                                 │
 │   └── Tailscale node "and-worker"                                                             │
 └──────────────────────────────────────────────────────────────────────────────────────────────┘
```

## B. Port map (defaults, all bound to `tailscale0`, not LAN)

| Node | Service | Port | Bind | Auth |
|---|---|---|---|---|
| Mac-H | OpenHands UI | 3000 | tailnet only | session |
| Mac-H | git (ssh) | 22 | tailnet only | SSH key |
| Mac-H | worker coordinator | 8410 | tailnet only | token |
| Mac-I | worker agent | 8411 | tailnet only | token |
| Mac-A | worker agent | 8412 | tailnet only | token |

> Nothing listens on `0.0.0.0` except the SSH key. Web + APIs are reachable **only inside the
> tailnet**; helpers route user auth over Tailscale identity.

## C. Request lifecycle (sequence)

1. Team member opens `https://harns.tailnet..ts.net` (OpenHands).
2. Describes task → OpenHands spawns an agent session on Mac-H.
3. Agent (Claude/Codex) reads repo, writes code on a **feature branch**, and **pushes**.
4. Coordinator (Mac-H) sees the new ref and dispatches:
   - `Mac-I` → gradle/xcodebuild on that ref → iOS test result.
   - `Mac-A` → gradle/androidTest on that ref → Android test result.
5. Each worker writes `worker-result.json` (pass/fail / logs / artifact path) back.
6. Agent reads results, fixes, pushes again → loop until green.
7. Agent opens **PR**; team reviews in browser; merges.

## D. Failure / handoff semantics (design for replacement)

- Worker down → coordinator marks node `DEGRADED`, alerts, keeps queue.
- One Mac dies → re-run the **bootstrap script** for its role on a spare identical Mac; the
  role (not hostname) is re-discovered. Zero leader-state stored on the dead node.
- LLM error → fallback provider (router retries Anthropic→OpenRouter) with circuit breaker.

## E. Secrets layout

| Secret | Location | Used by |
|---|---|---|
| LLM API key (Anthropic/OpenRouter) | Mac-H Keychain → env to agent | harness |
| Tailscale auth key | per-node `tailscale up` | all |
| SSH deploy key | Mac-H `~/.ssh` | all |
| iOS signing certs + provisioning | Mac-I Keychain | iOS worker |
| Android keystore | Mac-A Keychain/encrypted | Android worker |
| Coordinator↔worker token | shared secret in repo `TEMPLATES/` (not committed) | H/I/A |