#!/usr/bin/env bash
set -euo pipefail

lab_prefix="clab-internet-edge"
ctrl_1="${lab_prefix}-tpe10-bb-rr-ctrl-r1"
ctrl_2="${lab_prefix}-tpe10-bb-rr-ctrl-r2"

restore_ctrl() {
  docker start "$ctrl_1" "$ctrl_2" >/dev/null 2>&1 || true
}
trap restore_ctrl EXIT

vtysh() {
  local node="$1"
  shift
  docker exec "${lab_prefix}-${node}" vtysh "$@"
}

wait_for_preference() {
  local preference="$1"

  for attempt in $(seq 1 30); do
    if vtysh tpe10-bb-core-t1-r1 -c "show bgp ipv4 unicast 22.22.0.0/16" 2>/dev/null |
         grep -Eq "localpref ${preference},.*best" &&
       vtysh tpe10-bb-core-t1-r1 \
         -c "show bgp ipv6 unicast 2001:db8:6520::/48" 2>/dev/null |
         grep -Eq "localpref ${preference},.*best"; then
      return 0
    fi
    sleep 1
  done

  echo "ERROR: Core did not select LOCAL_PREF ${preference}." >&2
  return 1
}

check_forwarding() {
  docker exec "${lab_prefix}-service" \
    ping -I 203.0.113.10 -c 1 -W 1 22.22.0.1 >/dev/null
  docker exec "${lab_prefix}-service" \
    ping -6 -I 2001:db8:6500:100::10 -c 1 -W 1 \
      2001:db8:6520::1 >/dev/null
}

echo "Stopping tpe10-bb-rr-ctrl-r1 to verify tpe10-bb-rr-ctrl-r2 takeover..."
docker stop -t 1 "$ctrl_1" >/dev/null
wait_for_preference 300
check_forwarding
echo "tpe10-bb-rr-ctrl-r2 preserved the policy route and forwarding"

echo "Stopping tpe10-bb-rr-ctrl-r2 to verify fail-open RR-EXT fallback..."
docker stop -t 1 "$ctrl_2" >/dev/null
wait_for_preference 200
check_forwarding
echo "PASS: Core fell back to RR-EXT and forwarding remained healthy."
