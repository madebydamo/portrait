#!/bin/sh
# Production change that would fail this: skip install when PORTRAIT_SANDBOX_FW is
# unset, or ACCEPT uid-999 traffic to lo beyond 127.0.0.1:53 (e.g. karakeep :3000).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/scripts/apply-sandbox-fw.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

run_fw() {
  state=$1
  shift
  mkdir -p "$state/bin"
  cat >"$state/bin/mock-iptables" <<'MOCK'
#!/bin/sh
set -eu
bin=$(basename "$0")
dir="${MOCK_IPTABLES_STATE:?}/$bin"
mkdir -p "$dir"
rules="$dir/rules"
touch "$rules"
printf '%s\n' "$*" >>"$dir/cmds"
if [ "${MOCK_IPTABLES_DENY:-}" = "1" ]; then
  echo "iptables: Permission denied (you must be root)" >&2
  exit 1
fi
cmd=$1
shift
case "$cmd" in
  -I)
    # -I OUTPUT 1 <spec...>
    table=$1
    pos=$2
    shift 2
    line="-A $table $*"
    tmp=$(mktemp)
    if [ "$pos" = "1" ]; then
      printf '%s\n' "$line" >"$tmp"
      cat "$rules" >>"$tmp"
    else
      cat "$rules" >"$tmp"
      printf '%s\n' "$line" >>"$tmp"
    fi
    mv "$tmp" "$rules"
    ;;
  -D)
    table=$1
    num=$2
    tmp=$(mktemp)
    awk -v n="$num" 'NR!=n {print}' "$rules" >"$tmp"
    mv "$tmp" "$rules"
    ;;
  -S)
    echo "-P OUTPUT ACCEPT"
    cat "$rules"
    ;;
  -L)
    echo "Chain OUTPUT (policy ACCEPT)"
    echo "num  target     prot opt source               destination"
    i=0
    while IFS= read -r line; do
      i=$((i + 1))
      echo "$i    $line"
    done <"$rules"
    ;;
  *)
    echo "mock-iptables: unhandled: $cmd $*" >&2
    exit 1
    ;;
esac
MOCK
  chmod +x "$state/bin/mock-iptables"
  for name in iptables iptables-nft iptables-legacy ip6tables ip6tables-nft ip6tables-legacy; do
    ln -sf mock-iptables "$state/bin/$name"
  done
  MOCK_IPTABLES_STATE=$state PATH="$state/bin:$PATH" "$@"
}

# --- unset PORTRAIT_SANDBOX_FW still installs, and lo is DNS-only ---
state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT
unset PORTRAIT_SANDBOX_FW || true
out=$(run_fw "$state" "$SCRIPT" 2>&1) || fail "install exited $? without PORTRAIT_SANDBOX_FW: $out"
printf '%s\n' "$out" | grep -q 'VPN-only egress installed' \
  || fail "expected install without PORTRAIT_SANDBOX_FW, got: $out"

v4="$state/iptables-nft/rules"
[ -s "$v4" ] || fail "no iptables-nft rules written"

grep -q 'portrait-sandbox-drop' "$v4" || fail "missing uid-999 DROP: $(cat "$v4")"
grep -q 'portrait-sandbox-tun' "$v4" || fail "missing tun0 ACCEPT: $(cat "$v4")"
grep -q 'portrait-sandbox-dns-udp' "$v4" || fail "missing lo DNS/udp: $(cat "$v4")"
grep -q 'portrait-sandbox-dns-tcp' "$v4" || fail "missing lo DNS/tcp: $(cat "$v4")"

# Localhost needed for outbound: loopback DNS to 127.0.0.1:53 only.
# A bare lo ACCEPT (or any lo accept not pinned to dport 53) is the karakeep hole.
if grep -- '-o lo' "$v4" | grep -v -- '--dport 53' | grep -q .; then
  fail "lo ACCEPT is not DNS-only (would allow localhost:3000): $(grep -- '-o lo' "$v4")"
fi
if grep -E -- '--dport 3000|-d 127\.0\.0\.[0-9]+ -j ACCEPT|-o lo -j ACCEPT' "$v4"; then
  fail "localhost/service ACCEPT present: $(cat "$v4")"
fi
grep -q -- '-o lo -d 127.0.0.1 -p udp --dport 53 -j ACCEPT' "$v4" \
  || fail "missing exact udp/53 whitelist: $(cat "$v4")"
grep -q -- '-o lo -d 127.0.0.1 -p tcp --dport 53 -j ACCEPT' "$v4" \
  || fail "missing exact tcp/53 whitelist: $(cat "$v4")"

v6="$state/ip6tables-nft/rules"
grep -q 'portrait-sandbox-drop6' "$v6" || fail "missing IPv6 DROP: $(cat "$v6")"
if grep -q -- '-j ACCEPT' "$v6"; then
  fail "IPv6 must not ACCEPT localhost (::1) or anything else: $(cat "$v6")"
fi

# --- no NET_ADMIN: skip (local compose) unless required ---
deny=$(mktemp -d)
trap 'rm -rf "$state" "$deny"' EXIT
out=$(MOCK_IPTABLES_DENY=1 run_fw "$deny" "$SCRIPT" 2>&1) || fail "denied iptables should skip, got $?: $out"
printf '%s\n' "$out" | grep -qi 'skip' || fail "expected skip when iptables denied: $out"

req=$(mktemp -d)
trap 'rm -rf "$state" "$deny" "$req"' EXIT
if out=$(PORTRAIT_SANDBOX_FW=1 MOCK_IPTABLES_DENY=1 run_fw "$req" "$SCRIPT" 2>&1); then
  fail "PORTRAIT_SANDBOX_FW=1 must fail-closed when iptables denied: $out"
fi

# --- nft works, legacy table missing: still install (Gluetun/Ubuntu nft-only) ---
half=$(mktemp -d)
trap 'rm -rf "$state" "$deny" "$req" "$half"' EXIT
mkdir -p "$half/bin"
# Reuse mock, but make *-legacy unusable.
cat >"$half/bin/mock-iptables" <<'MOCK'
#!/bin/sh
set -eu
bin=$(basename "$0")
case "$bin" in
  *legacy)
    echo "$bin: can't initialize iptables table \`filter': Table does not exist" >&2
    exit 1
    ;;
esac
dir="${MOCK_IPTABLES_STATE:?}/$bin"
mkdir -p "$dir"
rules="$dir/rules"
touch "$rules"
cmd=$1
shift
case "$cmd" in
  -I)
    table=$1; pos=$2; shift 2
    tmp=$(mktemp)
    printf '%s\n' "-A $table $*" >"$tmp"
    cat "$rules" >>"$tmp"
    mv "$tmp" "$rules"
    ;;
  -S) echo "-P OUTPUT ACCEPT"; cat "$rules" ;;
  -L)
    echo "Chain OUTPUT (policy ACCEPT)"
    i=0
    while IFS= read -r line; do
      i=$((i + 1))
      echo "$i    $line"
    done <"$rules"
    ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$half/bin/mock-iptables"
for name in iptables iptables-nft iptables-legacy ip6tables ip6tables-nft ip6tables-legacy; do
  ln -sf mock-iptables "$half/bin/$name"
done
out=$(MOCK_IPTABLES_STATE=$half PATH="$half/bin:$PATH" "$SCRIPT" 2>&1) \
  || fail "nft-only install exited $?: $out"
printf '%s\n' "$out" | grep -q 'VPN-only egress installed' \
  || fail "expected nft-only install, got: $out"
grep -q 'portrait-sandbox-drop' "$half/iptables-nft/rules" \
  || fail "nft-only missing DROP"
[ ! -e "$half/iptables-legacy/rules" ] || fail "legacy should not have been written"

echo "ok"
