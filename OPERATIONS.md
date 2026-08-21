# OPERATIONS — zero-maintenance watchdogs & recovery

The farm minimises babysitting, but **Macs sleep and processes leak**. These daemons keep it
self-healing with almost no human input.

## 1. Keep-awake (caffeinate) — all 3 nodes
Prevents sleep-mid-build at 3am. Add to each Mac's Login Items (or LaunchDaemon):
```bash
$ pmset repeat start  # require wake auth off
caffeinate -dimsut 2592000 &   # process running indefinitely
```
Or `TEMPLATES/keep-awake.sh` marked "open at login".

## 2. Health broadcast (ping the loop)
`TEMPLATES/loop-alert.sh` — a small Hermes/netcat client on each node pings the coordinator
every 90s; a missing ping for 5 min triggers an alert to your existing Telegram/WhatsApp:
- `ios-worker`/`and-worker` → coordinator: they pull builds and test; if a build returns
  `worker-result.json` not-green, alert + queue retry.
- coordinator → your phone if 2 workers gone at once.

## 3. Self-heal restart
If the coordinator or a worker process dies (pid not alive / healthz 503), a launchd/systemd
watchdog restarts it idempotently. Worker jobs are **queued** (git-ref based) so a restart
picks up the pending ref without losing work.

## 4. Credential / signing rotation calendar
- iOS/Android signing certs expire → set a **calendar reminder** 30 days out.
- LLM key rotation every 90 days (your provider console) → update Keychain + repo env.
- Tailscale machine ACK `/reset` yearly.

## 5. Disaster/recovery playbook (keep in a `/docs/` or OPERATIONS.md you trust)
| Failure | Recovery (≤ 30 min except otherwise) |
|---|---|
| Mac-I dead | Bootstrap spare Mac via `TEMPLATES/ios_worker` + import signing from encrypted backup (30–45 min) |
| Mac-A dead | same for Android |
| Mac-H dead | Highest touch: re-install OpenHands + coordinator + LLM key from Keychain backup (~45 min) |
| Only one worker alive | Coordinator runs in DEGRADED (builds one platform, queues other) |
| Key leak | Rotate provider key + `tailscale up --reset`, revoke signed mac? |

## 6. Logging (for your audit + postmortem)
Each node → `/var/log/devfarm/`; coordinator mirrors to `/var/log/devfarm/coord/`; keep 30d.
You can answer "who asked for X, when did Mac-I fail" from there.

## 7. Backups — do once a week, forget
- `~/repos/company.git` (the origin) + `TEMPLATES/` + proof the farm is green →
  a SOAK bucket (or another node). 
- Signing material **off-box** (encrypted backup, ideally a vault you control).

## 8. Alerting ❚ channels
- Out-of-band to **company WhatsApp/Telegram** (you already bridge these with Hermes).
- In-browser: OpenHands notifications mention a worker halted; don't let a sleeper placeholder
  pass as "done".

---

### Gate (weekly 15-min ops checklist)
```
□ tailscale status → all 3 healthy, ACLs unchanged
□ coordinator /healthz 200
□ 0 builds failed in last 7 days (grep coordinator log)
□ both workers returned ≥1 green build
□ signing certs > 30 days from expiry
```
Copy/re-use from `TEMPLATES/ops-check.md`.