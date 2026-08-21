# RISKS & OPEN DECISIONS

Confirm these with your team **before** burning Phase 5 wiring time. Each has a default.

## Open decisions
1. **Hosting of the coordination state.** OpenHands runs on Mac-H; the worker queue is just
   git-refs. Default: all state on Mac-H. ⚠️ A non-persistent, non-distributed queue is the
   biggest single point of failure → mitigation: logs to repo + one spare Mac bootstrap.
2. **LLM provider(s).** Claude (Anthropic) vs OpenRouter aggregation vs DeepSeek.
   Default recommended: **OpenRouter primary, Anthropic fallback** (max uptime, toggle keys
   without rebuild).
3. **Authentication for the browser door.** Options: Tailscale identity alone, or OpenHands
   password, or OIDC to Google/Entra. Default: **Tailscale identity + strong OpenHands
   password** until SSO is worth wiring.
4. **Physical-device testing needs.** Do you need real iPhones/Androids in a lab, or are
   simulators enough for v1? Default: **simulators** (zero hardware-cage cost).
5. **Billing/quota per teammate.** v1 = coarse login only. Decide whether finance needs
   per-user spend lines → if yes, add a thin auth proxy in phase 2 (not now).

## Risks (could end the project if ignored)
| Risk | Likelihood/Impact | Mitigation |
|---|---|---|
| Macs sleep → missed 3am builds | High / High | keep-awake daemon + alert (OPERATIONS §1) |
| LLM key leak | Low / High | Keychain + provider spend cap + rotation (SECURITY §6) |
| One worker dies, builds block | Med / Med | worker is replaceable via bootstra; DEGRADED mode (PLAN §D) |
| OpenHands agent runs shell dangerously | Med / High | sandbox + repo-scoped + human merge gate (SECURITY §3) |
| Loss of signing certs | Low / Critical | off-box encrypted backup (OPERATIONS §7) |
| Team "loves Devin" and rejects a browser that differs | Med / High | keep OpenHands UI, add PR review + co-watching; pilot parallel for 1–2 sprints (IMPL §7) |

## Foundational assumption to keep honest
**The farm is not "3 Macs coding"; it's "1 browser + 3 Macs executing"**. If the company needs
*the agent to think about* huge codebases with real parallel multi-device testing and
enterprise audit, the 3-Mac farm is under-spec — revisit a managed option. The farm wins for
mobile-loop (iOS+Android) dev work *with your own signing + team already using Tailscale*.