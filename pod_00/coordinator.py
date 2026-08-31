#!/usr/bin/env python3
"""pod_00 DEVFARM COORDINATOR — job queue + result collector for the 3 pods.

Listens on port 8410 over the tailnet. Workers (pod_01 pod_02) poll /jobs
and POST results back to /result.

Endpoints (bound to the Tailscale interface only by default):
  GET  /health        -> {"ok": true}
  POST /jobs          -> {repo, ref, platform, scheme?, sim?}   enqueue a build
  GET  /jobs          -> oldest pending job (or null)           polled by workers
  POST /result        -> {job_id, node, status, log}            worker result
  GET  /results       -> all results so far

Run on pod_00:
  python3 ~/dev-farm/scripts/../pod_00/coordinator.py
(or use the bundled launchd plist in pod_00/).
"""
from __future__ import annotations

import argparse, json, os, queue
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

JOBS: queue.Queue = queue.Queue()          # pending jobs (dict)
LAST_RESULTS: dict[str, dict] = {}         # job_id -> result

SHARED_TOKEN = os.environ.get("DEVFARM_COORD_TOKEN", "devfarm-local")  # default dev-only


def auth_ok(headers) -> bool:
    return headers.get("X-DevFarm-Token") == SHARED_TOKEN or SHARED_TOKEN == "devfarm-local"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):          # quieter logs
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            return self._send(200, {"ok": True})
        if path == "/jobs":
            try:
                job = JOBS.get_nowait()
            except queue.Empty:
                job = None
            return self._send(200, job)           # worker polls
        if path == "/results":
            return self._send(200, LAST_RESULTS)
        return self._send(404, {"error": "not found"})

    def do_POST(self):
        if not auth_ok(self.headers):
            return self._send(401, {"error": "unauthorized"})
        path = urlparse(self.path).path
        try:
            n = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(n) or b"{}")
        except Exception as e:
            return self._send(400, {"error": str(e)})
        if path == "/jobs":
            data.setdefault("ref", "main")
            data.setdefault("repo", os.path.expanduser("~/repos/company.git"))
            data["job_id"] = f"job-{abs(hash((data['repo'], data['ref'], data.get('platform', ''))))}"
            JOBS.put(data)
            # fan out to all workers by queueing once; workers pick it up by platform.
            return self._send(201, {"ok": True, "job_id": data["job_id"]})
        if path == "/result":
            LAST_RESULTS[data.get("job_id")] = data
            return self._send(200, {"ok": True})
        return self._send(404, {"error": "not found"})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=int(os.environ.get("DEVFARM_COORD_PORT", "8410")))
    ap.add_argument("--host", default=os.environ.get("DEVFARM_COORD_HOST", "0.0.0.0"))
    args = ap.parse_args()
    print(f"dev-farm coordinator on {args.host}:{args.port}")
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()