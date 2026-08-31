# Self-Hosted Devin-Style Code-Pod Farm on 3 Macs

**Public repo.** Clone on any of the 3 Macs to provision your pods. Self-hosted,
browser-based coding-agent platform running entirely on **3 macOS laptops**, behind a
**Tailscale VPN**, with a **Claude/Codex brain** and **dedicated iOS + Android build/test
workers**.

| Pod | Mac | Role |
|---|---|---|
| **pod_00** | Mac-H (HARNS) | Orchestrator + Brain + Browser door (OpenHands) |
| **pod_01** | Mac-A (AND) | Android build/test worker |
| **pod_02** | Mac-I (IOS) | iOS build/test worker |

---

## TL;DR

| Devin (managed) | This plan (self-hosted) |
|---|---|
| Cloud-hosted agent, billed per task | Agents on your own 3 Macs, API-token cost only |
| Browser team UI | OpenHands browser UI (Devin-like) on the harness Mac |
| Managed provisioning | You wire the 3 nodes + signing once |
| Single vendor lock-in | Cloud-LLM-agnostic (Claude / Codex / OpenRouter) |
| Android + iOS build box built-in | Dedicated Mac per platform (mandatory anyway for iOS) |

**Not a clone of Devin, a cheaper equivalent**: your team keeps the "request a task →
watch the agent work → review the result" loop in a browser, while the reasoning runs on
your hardware + your cloud API keys instead of Devin's managed fleet.

---

## Automated provisioning (run on each pod)

Everything is scripted and idempotent. Start from a fully blank Mac.

### 1. Blank Mac — ONE line (installs CLT + Homebrew + git, clones repo)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Simao-Lopes/dev-farm/main/scripts/boot.sh)"
```

### 2. Comms FIRST — run on ALL THREE pods before any role suite

Comms (Tailscale mesh + SSH between the pods) must be up before pod_00 can
dispatch builds to pod_01/pod_02.

```bash
# on the Mac that will be pod_00
~/dev-farm/scripts/01-comms.sh pod_00
# on the other two:
~/dev-farm/scripts/01-comms.sh pod_01
~/dev-farm/scripts/01-comms.sh pod_02
```

Exchange the public keys each script prints (add each pod's key to the other
two's `~/.ssh/authorized_keys`). Verify from pod_00:

```bash
tailscale status          # all 3 named nodes online
ssh pod_01 hostname       # -> pod_01
ssh pod_02 hostname       # -> pod_02
```

### 3. Role suites — only after comms are up

```bash
~/dev-farm/scripts/pod_00.sh    # on pod_00: orchestrator, OpenHands, LLM brain, git origin
~/dev-farm/scripts/pod_01.sh    # on pod_01: Android toolchain + worker :8412
~/dev-farm/scripts/pod_02.sh    # on pod_02: iOS toolchain + worker :8411
```

The coordinator (job queue + result collector) lives at `pod_00/coordinator.py`
— run it on pod_00 after the suites are installed.

---

## Repository layout

```
dev-farm/
├── README.md               ← you are here
├── PLAN.md                 ← architecture, nodes, data flow
├── IMPLEMENTATION.md       ← phased, step-by-step build
├── SCHEMATIC.md            ← ASCII + textual topology
├── SECURITY.md            ← VPN, auth, secrets, compliance
├── COSTS.md                ← Devin vs self-hosted comparison
├── OPERATIONS.md           ← watchdogs, alerts, zero-maintenance
└── TEMPLATES/              ← example configs you adapt
    ├── loop-alert.sh
    ├── tailnet-acl.example.json
    ├── keep-awake.sh
    └── openhands-env.example

scripts/                    ← automated provisioning (run on each pod)
    ├── boot.sh             ← ONE-liner for a blank Mac (CLT + brew + clone)
    ├── lib.sh              ← shared helpers
    ├── 01-comms.sh         ← COMMS FIRST: Tailscale mesh + SSH between pods
    ├── pod_00.sh           ← orchestrator: OpenHands, LLM brain, git origin
    ├── pod_01.sh           ← Android: toolchain + worker agent
    └── pod_02.sh           ← iOS: toolchain + worker agent

pod_00/
    └── coordinator.py      ← job queue + result collector (:8410)
```

> Everything here is a **living document**: the repo is the system-of-record. Update it
> when you change a node role, add a credential, or cut a risk.
