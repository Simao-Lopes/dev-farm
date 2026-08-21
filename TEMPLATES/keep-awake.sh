#!/usr/bin/env bash
# keep-awake.sh — prevent sleep on a dev-farm Mac. Add to Login Items / LaunchAgent.
# Usage: keep-awake.sh   (turns on caffeinate + prevents display sleep)
set -euo pipefail

# Prevent system sleep (d) + display dim (i) + disk idle (s) + sleep (m)
# 2592000 = 30 days; process runs until killed.
caffeinate -dimsut 2592000 >/dev/null 2>&1 &
echo "caffeinate started: pid $!"

# Optional: also prevent App Nap on the Node processes if any.
# defaults write NSGlobalDomain NSAppSleepDisabled -bool YES
echo "keep-awake armed on $(hostname)"