# COSTS — Devin vs self-hosted farm

> Figures are indicative (2026). How to think about it: Devin bills **per task/agent-hour**;
> the farm pays **fixed tokens + Apple/Google fees** and repurposes hardware you already own.

## A. Devin (managed) — recurring
| Line | Est. |
|---|---|
| Seat/subscription (per user, billed) | $20–$50+/user/mo typical |
| Per-agent/task add-ons | variable, can dominate |
| Multi-user, 5-eng | $100–$250/mo and climbing with usage |
| **Total (illustrative, 5 users)** | **$120–$300+/mo**, usage-scaled |

## B. Self-hosted on 3 Macs — recurring (money)
| Line | Est. |
|---|---|
| Anthropic/OpenRouter tokens (code agent) | $?(tokens) — variable, e.g. $2–$20/mo dev off-peak in this farm |
| Apple Developer ($99/yr) + TestFlight | ~$8/mo amortized |
| Google Play (one-time $25) | ~$2/mo amortized |
| Tailscale personal/team tier | $0–$6/user/mo (free under 3 nodes) |
| **Total (illustrative, farm)** | **~$10–$40/mo** mostly tokens |

### Threshold
Roughly: if Devin's bill exceeds ~**1–2 sprints worth of API** per month, the farm wins. For a
small company burning Devin creds weekly, the farm pays for its own ops in the first months.

## C. Non-monetary costs (the real "price")
- **Ops labor:** ~2 evenings to wire (Phases 1–5), then ~30 min/wk maintenance. This is the
  actual non-zero line — Devin abstracts it away.
- **Failure RPO:** you hold signing keys + a device farm; a dead/missing worker delays a build.
- **Missing features vs Devin:** fine billing, some automated-hardware testing, and the
  polished SaaS "watch the whole thing" panel need OpenHands customisation.

## D. When NOT to do this
- Compliance demands a *managed* vendor + audit trail (defer; you'd need enterprise Devin).
- You need it THIS WEEK and have no 2 evenings to wire it.
- Tests must run on **many** physical devices (Linux/Windows desktop too) — the 3-Mac farm
  only covers iOS+Android mobile loops.

---

*Numbers are what to sanity-check with your actual token usage; the structural claim (fixed
fees vs per-task) holds regardless.*