#!/usr/bin/env bash
# loop-alert.sh — health ping + alert. Runs every 90s from each node (cron / LaunchAgent).
# Pings the coordinator; if a node is down too long, alerts the company chat.
set -euo pipefail

COORD_HOST="${COORD_HOST:-harns}"      # tailnet hostname
COORD_HEALTH="http://${COORD_HOST}:8410/healthz"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-https://hooks.example.com/whatsapp}"  # your Hermes/WhatsApp
NODE_NAME="$(hostname)"

STATUS="$(curl -fsS -m 5 "${COORD_HEALTH}" 2>/dev/null || echo DOWN)"

if [ "${STATUS}" = "DOWN" ]; then
  # alert only after repeated failures to avoid noise — write a marker file
  MARK="/tmp/devfarm_${NODE_NAME}_down"
  if [ -e "${MARK}" ]; then
    curl -fsS -X POST -H 'Content-Type: application/json' \
      -d "{\"text\":\"🚨 ${NODE_NAME} lost coordinator ${ALERT_COORD_HOST:-harns}\"}" \
      "${ALERT_WEBHOOK}" >/dev/null 2>&1 || true
  else
    touch "${MARK}"
  fi
else
  rm -f "/tmp/devfarm_${NODE_NAME}_down"
fi
exit 0