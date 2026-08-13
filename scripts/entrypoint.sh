#!/bin/sh
set -eu
/usr/local/bin/apply-sandbox-fw.sh
if [ "${PORTRAIT_SANDBOX_FW:-}" = "1" ]; then
  # Re-apply if Gluetun restores its OUTPUT snapshot.
  trap '' HUP
  (
    while true; do
      sleep 15
      /usr/local/bin/apply-sandbox-fw.sh || echo "portrait-sandbox-fw: reapply failed" >&2
    done
  ) &
fi
cd /home/damo
exec ./server
