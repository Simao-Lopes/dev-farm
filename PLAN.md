# PLAN — Architecture

## 1. Goal
Stand up a Devin-equivalent, browser-accessible, agentic **code-development platform** for
the company that lives **entirely on 3 macOS laptops**, replaces the Devin subscription, and
removes the managed-cloud dependency — while keeping the team UX (request → watch → review).

## 2. Node roles (the 3 Macs)

| Node | Role | Responsibilities |
|---|---|---|
| **pod_00 (Mac-H, HARNS)** | Orchestrator + Brain + Browser door | OpenHands (browser UI), Claude Code/Codex as LLM driver, repo origin/clones, task queue, credential vault, Tailscale host **and** exit node |
| **pod_02 (Mac-I, IOS)** | iOS build/test worker | Xcode, iOS Simulator, physical-device provisioning, TestFlight build+upload, signing certs |
| **pod_01 (Mac-A, AND)** | Android build/test worker | Android Studio, AVD emulators, Gradle builds, APK/AAB signing, real-device loops |

> Roles are **decoupled by SSH + git + Tailscale**, not by shared filesystem. Each node can
> be replaced by a sibling Mac with no leader reconfiguration (the coordinator talks to
> roles, not hostnames).

## 3. Three layers (the mental model)

1. **Team surface (browser)** — OpenHands web UI. This is what the team "loves like Devin":
   a button → describe task → watch the agent → review diff/PR.
2. **Reasoning (LLM brain)** — Claude Code or Codex running **on Mac-H**, calling Anthropic
   / OpenRouter *from the cloud* (cheap, no local-GPU). Make it provider-vaulted so the route
   can change without touching the UI.
3. **Executive layer (compilers + verifiers)** — Mac-I and Mac-A actually compile, run
   simulators/emulators, run tests, and report pass/fail back into the loop. This is work
   Devin monetises and cloud-only agents **cannot do for iOS** (macOS is mandatory).

## 4. Data flow (request → review)

```
Team in browser ── Tailscale ──> Mac-H: OpenHands UI
                                       │  task
                                       ▼
                                 Agent loop (Claude/Codex)
                                       │  edits + builds
            ┌──────────────────────────┼──────────────────────────┐
            ▼                          ▼                          ▼
       Mac-H (FE/BE + orchestrate)  Mac-I (iOS Xcode/sim)    Mac-A (Android gradle/emulator)
            │                    builds/tests               builds/tests
            └────────── reports pass/fail ────────────────────────────────┘
                                       │  PR + artifact
                                       ▼
                            Team reviews in browser
```

## 5. Key design choices (why these)

- **Tailscale, not a hand-rolled VPN.** WireGuard underneath, identity-based auth, per-node
  ACLs, NAT-traversal. Your 3 Macs + any teammate joining the tailnet get a private mesh
  **with zero per-device VPN config** — the "robust" part is handled by Tailscale's
  coordination, and it works across home/office/mobile without holes.
- **OpenHands as the browser door.** Closest self-hosted analogue to Devin's UI. Runs on
  Mac-H; team reaches it via `https://<tailnet-name>/` — works on phone+desktop like Devin.
- **Cloud LLM, local execution.** Reasoning in the cloud (Claude/Codex/OpenRouter), native
  compile on the Macs. This is the cost-killer: you pay token fees, not per-task Devin fees.
- **Git as the handoff layer.** Agents commit to feature branches, push PRs, and the build
  workers test a specific ref. No fragile shared-volume plumbing; git *is* the contract.
- **SSH/NFS-free worker contract.** Mac-I/A run a tiny long-lived agent that: pulls a branch,
  builds, tests, and writes a structured result JSON back via git/tailnet HTTP. Coordinator
  never needs to log into them per task.

## 6. What is intentionally NOT in scope v1
- Fine per-user billing/quota dashboards (OpenHands has coarse access; per-seat $ attribution
  is a phase-2 add).
- Production CI/CD (this is dev-loop agent work; Prod deploys stay separate/decrease later).
- Windows/Linux mobile targets (iOS+Android cover the ask).

## 7. Nodes' hardware expectations
- Mac-H: any Apple Silicon with ≥16GB (house the browser+agents comfortably).
- Mac-I: Apple Silicon w/ Xcode; enough disk for a couple of iOS simulator runtimes (~15–20GB).
- Mac-A: Apple Silicon w/ Android Studio + one AVD (~8–12GB disk).
- All three: keep-awake enabled, network-on (Tailscale node), autoplay off logs to `/var/log`.

## 8. Non-functional requirements
- **Security:** everything behind Tailscale ACLs; secrets in macOS **Keychain** (+ a vaulted
  env for the LLM key); iOS/Android **signing keys** never on disk unencrypted.
- **Availability:** watchdogs restart agent/loop on each node; alerts via a simple Telegram/
  WhatsApp bot (you already run one).
- **Maintainability:** declarative configs in repo `TEMPLATES/`; a bootstrap script per node;
  one doc per node role.
- **Cost:** zero infra capex (hardware exists), only LLM tokens + Apple dev account fee.