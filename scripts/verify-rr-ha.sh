#!/usr/bin/env bash
set -euo pipefail

lab_prefix="clab-internet-edge"
rr1="${lab_prefix}-rr1"

restore_rr1() {
  docker start "$rr1" >/dev/null 2>&1 || true
}
trap restore_rr1 EXIT

echo "Stopping rr1 to verify rr2 takeover..."
docker stop -t 1 "$rr1" >/dev/null

for attempt in $(seq 1 15); do
  if docker exec "${lab_prefix}-edge1" \
       vtysh -c "show bgp ipv4 unicast 22.22.0.0/16" 2>/dev/null |
       grep -q "2222" &&
     docker exec "${lab_prefix}-edge2" \
       vtysh -c "show bgp ipv4 unicast 11.11.0.0/16" 2>/dev/null |
       grep -q "1111" &&
     docker exec "${lab_prefix}-edge1" \
       vtysh -c "show bgp ipv6 unicast 2001:db8:6520::/48" 2>/dev/null |
       grep -q "2222" &&
     docker exec "${lab_prefix}-edge2" \
       vtysh -c "show bgp ipv6 unicast 2001:db8:6510::/48" 2>/dev/null |
       grep -q "1111" &&
     docker exec "${lab_prefix}-service" \
       ping -I 203.0.113.10 -c 1 -W 1 22.22.0.1 >/dev/null &&
     docker exec "${lab_prefix}-service" \
       ping -6 -I 2001:db8:6500:100::10 -c 1 -W 1 \
         2001:db8:6510::1 >/dev/null; then
    echo "PASS: IPv4/IPv6 routes and forwarding survived the rr1 failure."
    exit 0
  fi

  if [[ "$attempt" -eq 15 ]]; then
    echo "ERROR: rr2 did not preserve service after rr1 failed." >&2
    exit 1
  fi
  sleep 1
done
