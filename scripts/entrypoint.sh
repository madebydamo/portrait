#!/bin/sh
# The server installs the sandbox firewall (apply-sandbox-fw.sh) before it
# serves anything, refuses to start without it when PORTRAIT_SANDBOX_FW=1, and
# checks it before every sandbox and every 5 s (server/src/sandbox_fw.rs).
set -eu
cd /home/damo
exec ./server
