#!/usr/bin/env bash
set -euo pipefail

lab_prefix="clab-internet-edge"
originator_1="${lab_prefix}-tpe10-bb-org-t1-r1"

restore_originator() {
  docker start "$originator_1" >/dev/null 2>&1 || true
}
trap restore_originator EXIT

vtysh() {
  local node="$1"
  shift
  docker exec "${lab_prefix}-${node}" vtysh "$@"
}

echo "Stopping tpe10-bb-org-t1-r1 to verify Originator HA..."
docker stop -t 1 "$originator_1" >/dev/null

for attempt in $(seq 1 30); do
  tra_v4="$(vtysh tpe10-bb-tra-t1-r1 \
    -c "show bgp ipv4 unicast 203.0.113.0/24" 2>/dev/null || true)"
  tra_v6="$(vtysh tpe10-bb-tra-t1-r1 \
    -c "show bgp ipv6 unicast 2001:db8:6500::/48" 2>/dev/null || true)"
  transit_a="$(vtysh transit-a \
    -c "show bgp ipv4 unicast 203.0.113.0/24" 2>/dev/null || true)"
  transit_b="$(vtysh transit-b \
    -c "show bgp ipv4 unicast 203.0.113.0/24" 2>/dev/null || true)"

  if grep -Fq "10.255.0.42" <<<"$tra_v4" &&
     grep -Fq "fd00:6500::42" <<<"$tra_v6" &&
     grep -Eq "^[[:space:]]+205013 205013$" <<<"$transit_a" &&
     grep -Eq \
       "^[[:space:]]+205013 205013 205013 205013$" <<<"$transit_b" &&
     docker exec "${lab_prefix}-transit-a" \
       ping -I 11.11.0.1 -c 1 -W 1 203.0.113.10 >/dev/null &&
     docker exec "${lab_prefix}-transit-b" \
       ping -6 -I 2001:db8:6520::1 -c 1 -W 1 \
         2001:db8:6500:100::10 >/dev/null; then
    echo "PASS: r2 preserved aggregates, export policy, and forwarding."
    exit 0
  fi

  sleep 1
done

echo "ERROR: Originator failover did not converge within 30 seconds." >&2
exit 1
