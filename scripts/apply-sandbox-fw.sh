#!/bin/sh
# Restrict uid 999 egress when this container shares a VPN netns.
# Guest localhost is DNS-only (127.0.0.1:53) so shared-netns services
# such as karakeep :3000 stay unreachable. Everything else is tun0.
# PORTRAIT_SANDBOX_FW=1 is fail-closed (homeserver). Unset + no NET_ADMIN
# skips so local compose still starts.
#
# Two layers, each enough on its own:
#   - an nftables table of its own (inet portrait-sandbox). gluetun only
#     rewrites iptables' filter table (it restores its OUTPUT snapshot), never
#     this table, so the sandbox stays closed while gluetun does that;
#   - owner-match rules at the top of iptables' OUTPUT chain (nft and legacy
#     backends), as before.
# In nftables every base chain on the hook sees the packet, and a drop in any
# of them is final: gluetun's accepts cannot open what this table drops.
#
# --check: exit 0 when both layers are in place, 2 when only the iptables
# layer is missing or out of order (still closed), 1 when the nftables layer
# is missing. The server (server/src/sandbox_fw.rs) runs it before each
# sandbox and every 5 s, and installs again when it fails.
set -eu
UID_S=999
COMMENT_PREFIX=portrait-sandbox
NFT_TABLE=portrait-sandbox
STAMP=/run/portrait-sandbox-fw.installed
required=0
changed=
[ "${PORTRAIT_SANDBOX_FW:-}" = "1" ] && required=1
mode=install
[ "${1:-}" = "--check" ] && mode=check

backends() {
  kind=$1
  case "$kind" in
    4) nft=iptables-nft; legacy=iptables-legacy; any=iptables ;;
    6) nft=ip6tables-nft; legacy=ip6tables-legacy; any=ip6tables ;;
    *) echo "portrait-sandbox-fw: bad family $kind" >&2; return 1 ;;
  esac
  if command -v "$nft" >/dev/null 2>&1 && command -v "$legacy" >/dev/null 2>&1; then
    printf '%s\n%s\n' "$nft" "$legacy"
  elif command -v "$any" >/dev/null 2>&1; then
    printf '%s\n' "$any"
  fi
}

usable() {
  "$1" -S OUTPUT >/dev/null 2>&1
}

clear_rules() {
  table=$1
  i=0
  while [ "$i" -lt 30 ]; do
    i=$((i + 1))
    line=$("$table" -L OUTPUT -n --line-numbers 2>/dev/null | grep "$COMMENT_PREFIX" | head -1 | awk '{print $1}') || true
    [ -n "${line:-}" ] || break
    "$table" -D OUTPUT "$line" || break
  done
}

install_v4() {
  ipt=$1
  clear_rules "$ipt"
  # Insert at 1 so these beat Gluetun's later -o lo -j ACCEPT.
  # lo: only 127.0.0.1:53 (VPN DNS). No other localhost / shared-netns ports.
  "$ipt" -I OUTPUT 1 -m owner --uid-owner "$UID_S" -j DROP \
    -m comment --comment "${COMMENT_PREFIX}-drop" || return 1
  "$ipt" -I OUTPUT 1 -m owner --uid-owner "$UID_S" -o tun0 -j ACCEPT \
    -m comment --comment "${COMMENT_PREFIX}-tun" || return 1
  "$ipt" -I OUTPUT 1 -m owner --uid-owner "$UID_S" -o lo -d 127.0.0.1 -p tcp --dport 53 -j ACCEPT \
    -m comment --comment "${COMMENT_PREFIX}-dns-tcp" || return 1
  "$ipt" -I OUTPUT 1 -m owner --uid-owner "$UID_S" -o lo -d 127.0.0.1 -p udp --dport 53 -j ACCEPT \
    -m comment --comment "${COMMENT_PREFIX}-dns-udp" || return 1
  "$ipt" -I OUTPUT 1 -m owner --uid-owner "$UID_S" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT \
    -m comment --comment "${COMMENT_PREFIX}-est" || return 1
  "$ipt" -S OUTPUT 2>/dev/null | grep -q "${COMMENT_PREFIX}-drop" || {
    echo "portrait-sandbox-fw: $ipt OUTPUT missing drop rule" >&2
    return 1
  }
}

install_v6() {
  ipt=$1
  clear_rules "$ipt"
  "$ipt" -I OUTPUT 1 -m owner --uid-owner "$UID_S" -j DROP \
    -m comment --comment "${COMMENT_PREFIX}-drop6" || return 1
  "$ipt" -S OUTPUT 2>/dev/null | grep -q "${COMMENT_PREFIX}-drop6" || {
    echo "portrait-sandbox-fw: $ipt OUTPUT missing drop rule" >&2
    return 1
  }
}

# Comment names of the first rules in OUTPUT, space-separated.
first_rules() {
  "$1" -S OUTPUT 2>/dev/null | grep -v '^-P' | head -"$2" \
    | sed -n "s/.*\(${COMMENT_PREFIX}-[a-z0-9-]*\).*/\1/p" | tr '\n' ' '
}

# Our rules come first in OUTPUT, in this order (each -I 1 goes on top).
v4_ok() {
  [ "$(first_rules "$1" 5)" = "${COMMENT_PREFIX}-est ${COMMENT_PREFIX}-dns-udp ${COMMENT_PREFIX}-dns-tcp ${COMMENT_PREFIX}-tun ${COMMENT_PREFIX}-drop " ]
}

v6_ok() {
  [ "$(first_rules "$1" 1)" = "${COMMENT_PREFIX}-drop6 " ]
}

install_family() {
  kind=$1
  bins=$(backends "$kind")
  [ -n "$bins" ] || return 1
  ok=
  for ipt in $bins; do
    usable "$ipt" || continue
    if [ "$mode" = check ]; then
      if [ "$kind" = 4 ]; then v4_ok "$ipt" || return 1; else v6_ok "$ipt" || return 1; fi
      ok=1
      continue
    fi
    before=$("$ipt" -S OUTPUT 2>/dev/null || true)
    if [ "$kind" = 4 ]; then
      install_v4 "$ipt" || return 1
    else
      install_v6 "$ipt" || return 1
    fi
    [ "$before" = "$("$ipt" -S OUTPUT 2>/dev/null || true)" ] || changed=1
    ok=1
  done
  [ -n "$ok" ]
}

install_rules() {
  install_family 4 || {
    echo "portrait-sandbox-fw: no usable iptables" >&2
    return 1
  }
  install_family 6 || {
    echo "portrait-sandbox-fw: no usable ip6tables" >&2
    return 1
  }
}

# ── nftables layer ──────────────────────────────────────────────────────────

nft_ruleset() {
  # "table …" then "delete table …": replaces the table in one transaction.
  cat <<RULES
table inet $NFT_TABLE
delete table inet $NFT_TABLE
table inet $NFT_TABLE {
  chain output {
    type filter hook output priority -10; policy accept;
    meta skuid $UID_S meta nfproto ipv6 drop comment "${COMMENT_PREFIX}-drop6"
    meta skuid $UID_S ct state established,related accept comment "${COMMENT_PREFIX}-est"
    meta skuid $UID_S oifname "lo" ip daddr 127.0.0.1 udp dport 53 accept comment "${COMMENT_PREFIX}-dns-udp"
    meta skuid $UID_S oifname "lo" ip daddr 127.0.0.1 tcp dport 53 accept comment "${COMMENT_PREFIX}-dns-tcp"
    meta skuid $UID_S oifname "tun0" accept comment "${COMMENT_PREFIX}-tun"
    meta skuid $UID_S drop comment "${COMMENT_PREFIX}-drop"
  }
}
RULES
}

nft_ok() {
  command -v nft >/dev/null 2>&1 || return 1
  out=$(nft list chain inet "$NFT_TABLE" output 2>/dev/null) || return 1
  printf '%s\n' "$out" | grep -q 'hook output' || return 1
  printf '%s\n' "$out" | grep -q "comment \"${COMMENT_PREFIX}-drop6\"" || return 1
  printf '%s\n' "$out" | grep -q "comment \"${COMMENT_PREFIX}-drop\"" || return 1
}

install_nft() {
  command -v nft >/dev/null 2>&1 || {
    echo "portrait-sandbox-fw: nft not found" >&2
    return 1
  }
  nft_ok && return 0
  nft_ruleset | nft -f - || return 1
  nft_ok || {
    echo "portrait-sandbox-fw: nftables table missing after install" >&2
    return 1
  }
  changed=1
}

if [ "$mode" = check ]; then
  nft_ok || exit 1
  install_rules 2>/dev/null || exit 2
  exit 0
fi

nft_failed=
install_nft || nft_failed=1
if [ -n "$nft_failed" ] || ! install_rules; then
  if [ "$required" = 1 ]; then
    echo "portrait-sandbox-fw: required install failed" >&2
    exit 1
  fi
  echo "portrait-sandbox-fw: skipped (iptables/nftables not usable)"
  exit 0
fi

if [ -w /run ]; then
  : >"$STAMP"
fi
# Re-run whenever a check fails; only log when the rules moved.
[ -n "$changed" ] || exit 0
echo "portrait-sandbox-fw: uid=${UID_S} VPN-only egress installed (tun0=$(grep -c '^ *tun0:' /proc/net/dev || true))"
