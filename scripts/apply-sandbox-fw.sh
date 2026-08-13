#!/bin/sh
# Restrict uid 999 egress when this container shares a VPN netns.
# Disabled unless PORTRAIT_SANDBOX_FW=1 so local compose is unchanged.
set -eu
UID_S=999
COMMENT_PREFIX=portrait-sandbox

if [ "${PORTRAIT_SANDBOX_FW:-}" != "1" ]; then
  echo "portrait-sandbox-fw: skipped (PORTRAIT_SANDBOX_FW!=1)"
  exit 0
fi

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

install_rules() {
  v4=$(backends 4)
  [ -n "$v4" ] || {
    echo "portrait-sandbox-fw: iptables missing" >&2
    return 1
  }
  v6=$(backends 6)
  [ -n "$v6" ] || {
    echo "portrait-sandbox-fw: ip6tables missing" >&2
    return 1
  }

  for ipt in $v4; do
    install_v4 "$ipt" || return 1
  done
  for ipt in $v6; do
    install_v6 "$ipt" || return 1
  done
}

install_rules
echo "portrait-sandbox-fw: uid=${UID_S} VPN-only egress installed (tun0=$(grep -c '^ *tun0:' /proc/net/dev || true))"
