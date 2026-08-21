# SECURITY — company-grade hardening

**Threat model:** attacker gets a Mac, a tailnet device, or an API key. Defense-in-depth below.

## 1. Network (Tailscale)
- **Tailnet is the trust boundary.** Nothing binds to the local LAN or `0.0.0.0` except
  SSH. OpenHands/coordinator/workers all bind to `tailscale0`.
- **Least-privilege ACLs.** Example (edit `TEMPLATES/tailnet-acl.example.json`):
  - `team@example.com` → `tag:harness:3000` (browser only).
  - `tag:harness` ↔ `tag:ios-worker`/`tag:and-worker` on ports 22/8410/8411/8412.
  - No device may reach the other's signing material directly.
- **Enable MagicDNS + tailnet identity** for OpenHands so session auth is backed by SSO if
  available; otherwise enforce a strong OpenHands password + 2FA.
- **Rotation:** `tailscale up --reset` yearly; revoke a machine instantly by removing its node.

## 2. Secrets
- **LLM key:** Mac-H Keychain (not in repo, not in env files on disk).
- **iOS signing certs + provisioning profiles:** Mac-I Keychain; never copied to other nodes.
- **Android keystore:** Mac-A Keychain-backed; keep an encrypted backup off-box.
- **Coordinator ↔ worker token:** Appears in `TEMPLATES/` as a **placeholder only** — never
  commit a real token. Generate per-job (`python -c secrets.token_urlsafe`) or short-lived.
- **SSH:** one deploy key for the harness; worker pulls use the harness's forwarded key.

## 3. Agent safety (the "agent writes code" surface)
- OpenHands agents run **in a sandboxed workspace** with least privilege (no sudo by default,
  network egress where needed for build only).
- **Repos:** workers do `git fetch` + build/test of a **branch ref** — they never merge or
  push; only the harness merges (or a human via browser review).
- **Prompt-injection guardrails** (the real risk with long-lived coding agents): pin the
  agent to the repo's `AGENTS.md`, and disallow the bot from executing free-form shell outside
  the workspace. Add a **human-in-the-loop** merge gate in OpenHands (all PRs require review).

## 4. macOS host hardening (per Mac)
- **Gatekeeper + FileVault** enabled (disk encrypted → protecting signing keys at rest).
- **Auto-sleep OFF** on device workers (see OPERATIONS) + require admin password for wake.
- **Automatic updates ON** for OS + Xcode minor updates; schedule off-peak.
- **No guest account;** company user local-only; sudoers scoped.

## 5. Audit & logging
- Each node ships logs to `/var/log/devfarm/` (worker, coordinator, agent).
- Central HTTP/JSON log collector on Mac-H (keeps 30 days) so a post-incident review works.
- Coordinators log job + node + ref + result (you can grep "who built what when").

## 6. LLM provider key hygiene
- One **service** API key per provider, not your personal key. Set spend caps at the provider
  console (Anthropic/OpenRouter both support per-key budgets) — this is your Devin-replacement
  cost-line, so cap it.
- Fallback: route Anthropic→OpenRouter so a key breach or quota loss doesn't halt the farm.

## 7. Known non-goals (explicitly deferred, do not architect around them)
- Per-user billing/quota in OpenHands (coarse today) — decide later with a small auth proxy.
- Zero-trust for the build **devices themselves** (they hold signing keys — treat them as
  Tier-1 assets, physical access = full trust).