# Self-Hosted Devin-Style Agent Farm on 3 Macs

**Company-internal blueprint — private.** Replaces managed Devin with a self-hosted,
browser-based coding-agent platform running entirely on **3 macOS laptops**, behind a
**Tailscale VPN**, with a **Claude/Codex brain** and **dedicated iOS + Android build/test
workers**.

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
```

> Everything here is a **living document**: the repo is the system-of-record. Update it
> when you change a node role, add a credential, or cut a risk.