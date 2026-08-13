#!/bin/sh
# Restrict uid 999 egress when this container shares a VPN netns.
# Guest localhost is DNS-only (127.0.0.1:53) so shared-netns services
# such as karakeep :3000 stay unreachable. Everything else is tun0.
# PORTRAIT_SANDBOX_FW=1 is fail-closed (homeserver). Unset + no NET_ADMIN
# skips so local compose still starts.
set -eu
UID_S=999
COMMENT_PREFIX=portrait-sandbox
STAMP=/run/portrait-sandbox-fw.installed
required=0
[ "${PORTRAIT_SANDBOX_FW:-}" = "1" ] && required=1

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

install_family() {
  kind=$1
  bins=$(backends "$kind")
  [ -n "$bins" ] || return 1
  ok=
  for ipt in $bins; do
    usable "$ipt" || continue
    if [ "$kind" = 4 ]; then
      install_v4 "$ipt" || return 1
    else
      install_v6 "$ipt" || return 1
    fi
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

if ! install_rules; then
  if [ "$required" = 1 ]; then
    echo "portrait-sandbox-fw: required install failed" >&2
    exit 1
  fi
  echo "portrait-sandbox-fw: skipped (iptables not usable)"
  exit 0
fi

if [ -w /run ]; then
  : >"$STAMP"
fi
echo "portrait-sandbox-fw: uid=${UID_S} VPN-only egress installed (tun0=$(grep -c '^ *tun0:' /proc/net/dev || true))"
