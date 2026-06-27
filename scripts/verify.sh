#!/usr/bin/env bash
set -euo pipefail

lab_prefix="clab-internet-edge"

vtysh() {
  local node="$1"
  shift
  docker exec "${lab_prefix}-${node}" vtysh "$@"
}

echo "Waiting for IPv4 and IPv6 BGP routes..."
for attempt in $(seq 1 60); do
  if vtysh edge1 -c "show bgp ipv4 unicast 11.11.0.0/16" 2>/dev/null |
       grep -q "1111" &&
     vtysh edge1 -c "show bgp ipv4 unicast 22.22.0.0/16" 2>/dev/null |
       grep -q "2222" &&
     vtysh edge2 -c "show bgp ipv4 unicast 11.11.0.0/16" 2>/dev/null |
       grep -q "1111" &&
     vtysh edge2 -c "show bgp ipv4 unicast 22.22.0.0/16" 2>/dev/null |
       grep -q "2222" &&
     vtysh edge1 -c "show bgp ipv6 unicast 2001:db8:6510::/48" 2>/dev/null |
       grep -q "1111" &&
     vtysh edge1 -c "show bgp ipv6 unicast 2001:db8:6520::/48" 2>/dev/null |
       grep -q "2222" &&
     vtysh edge2 -c "show bgp ipv6 unicast 2001:db8:6510::/48" 2>/dev/null |
       grep -q "1111" &&
     vtysh edge2 -c "show bgp ipv6 unicast 2001:db8:6520::/48" 2>/dev/null |
       grep -q "2222" &&
     vtysh core1 -c "show bgp ipv4 unicast 11.11.0.0/16" 2>/dev/null |
       grep -q "1111" &&
     vtysh core1 -c "show bgp ipv4 unicast 22.22.0.0/16" 2>/dev/null |
       grep -q "2222" &&
     vtysh core1 -c "show bgp ipv6 unicast 2001:db8:6510::/48" 2>/dev/null |
       grep -q "1111" &&
     vtysh core1 -c "show bgp ipv6 unicast 2001:db8:6520::/48" 2>/dev/null |
       grep -q "2222" &&
     vtysh core2 -c "show bgp ipv4 unicast 11.11.0.0/16" 2>/dev/null |
       grep -q "1111" &&
     vtysh core2 -c "show bgp ipv4 unicast 22.22.0.0/16" 2>/dev/null |
       grep -q "2222" &&
     vtysh core2 -c "show bgp ipv6 unicast 2001:db8:6510::/48" 2>/dev/null |
       grep -q "1111" &&
     vtysh core2 -c "show bgp ipv6 unicast 2001:db8:6520::/48" 2>/dev/null |
       grep -q "2222"; then
    break
  fi

  if [[ "$attempt" -eq 60 ]]; then
    echo "ERROR: BGP routes did not converge within 60 seconds." >&2
    exit 1
  fi
  sleep 1
done

echo
echo "=== Edge IPv4 BGP summaries ==="
vtysh edge1 -c "show bgp ipv4 unicast summary"
vtysh edge2 -c "show bgp ipv4 unicast summary"

echo
echo "=== Edge IPv6 BGP summaries ==="
vtysh edge1 -c "show bgp ipv6 unicast summary"
vtysh edge2 -c "show bgp ipv6 unicast summary"

echo
echo "=== Route Reflector client checks ==="
for edge in edge1 edge2; do
  if docker exec "${lab_prefix}-${edge}" ip link show eth4 >/dev/null 2>&1; then
    echo "ERROR: ${edge} still has a direct Edge-to-Edge eth4 link." >&2
    exit 1
  fi
done
echo "edge1 and edge2 have no direct data-plane link"

for edge in edge1 edge2; do
  running_config="$(vtysh "$edge" -c "show running-config")"
  grep -Fq "bgp cluster-id 10.255.255.1" <<<"$running_config"
  [[ "$(grep -Fc "route-reflector-client" <<<"$running_config")" -eq 4 ]]
  echo "${edge}: core1/core2 are IPv4 and IPv6 RR clients"
done

for core in core1 core2; do
  ipv4_summary="$(vtysh "$core" -c "show bgp ipv4 unicast summary")"
  ipv6_summary="$(vtysh "$core" -c "show bgp ipv6 unicast summary")"
  grep -Fq "10.255.0.1" <<<"$ipv4_summary"
  grep -Fq "10.255.0.2" <<<"$ipv4_summary"
  grep -Fq "fd00:6500::1" <<<"$ipv6_summary"
  grep -Fq "fd00:6500::2" <<<"$ipv6_summary"
  echo "${core}: both redundant RR sessions are present"
done

echo
echo "=== Edge BFD peers ==="
vtysh edge1 -c "show bfd peers brief"
vtysh edge2 -c "show bfd peers brief"

echo
echo "=== Inbound bogon policy checks ==="
for node in edge1 edge2; do
  running_config="$(vtysh "$node" -c "show running-config")"
  as_path_policy="$(vtysh "$node" -c \
    "show bgp as-path-access-list PUBLIC-ASN-ONLY")"

  grep -Fq "deny 10.0.0.0/8 le 32" <<<"$running_config"
  grep -Fq "deny 172.16.0.0/12 le 32" <<<"$running_config"
  grep -Fq "deny 192.168.0.0/16 le 32" <<<"$running_config"
  grep -Fq "deny fc00::/7 le 128" <<<"$running_config"
  grep -Fq "filter-list PUBLIC-ASN-ONLY in" <<<"$running_config"
  grep -Fq "6451[2-9]" <<<"$as_path_policy"
  grep -Fq "42[0-8]" <<<"$as_path_policy"
  echo "${node}: RFC1918, ULA, and Private ASN filters are loaded"
done

echo
echo "=== No Peer-1/Peer-2 transit checks ==="
if vtysh transit-a -c "show bgp ipv4 unicast 22.22.0.0/16" |
     grep -Fq "BGP routing table entry for"; then
  echo "ERROR: Peer-2 IPv4 prefix leaked to Peer-1." >&2
  exit 1
fi
if vtysh transit-b -c "show bgp ipv4 unicast 11.11.0.0/16" |
     grep -Fq "BGP routing table entry for"; then
  echo "ERROR: Peer-1 IPv4 prefix leaked to Peer-2." >&2
  exit 1
fi
if vtysh transit-a -c "show bgp ipv6 unicast 2001:db8:6520::/48" |
     grep -Fq "BGP routing table entry for"; then
  echo "ERROR: Peer-2 IPv6 prefix leaked to Peer-1." >&2
  exit 1
fi
if vtysh transit-b -c "show bgp ipv6 unicast 2001:db8:6510::/48" |
     grep -Fq "BGP routing table entry for"; then
  echo "ERROR: Peer-1 IPv6 prefix leaked to Peer-2." >&2
  exit 1
fi
if docker exec "${lab_prefix}-transit-a" \
     ping -I 11.11.0.1 -c 1 -W 1 22.22.0.1 >/dev/null 2>&1 ||
   docker exec "${lab_prefix}-transit-b" \
     ping -I 22.22.0.1 -c 1 -W 1 11.11.0.1 >/dev/null 2>&1 ||
   docker exec "${lab_prefix}-transit-a" \
     ping -6 -I 2001:db8:6510::1 -c 1 -W 1 \
       2001:db8:6520::1 >/dev/null 2>&1 ||
   docker exec "${lab_prefix}-transit-b" \
     ping -6 -I 2001:db8:6520::1 -c 1 -W 1 \
       2001:db8:6510::1 >/dev/null 2>&1; then
  echo "ERROR: Peer-1 and Peer-2 can transit AS205013." >&2
  exit 1
fi
echo "Peer-1 and Peer-2 routes are isolated in both directions"

echo
echo "=== End-to-end data-plane tests ==="
docker exec "${lab_prefix}-service" \
  ping -I 203.0.113.10 -c 3 -W 1 11.11.0.1
docker exec "${lab_prefix}-service" \
  ping -I 203.0.113.10 -c 3 -W 1 22.22.0.1
docker exec "${lab_prefix}-service" \
  ping -6 -I 2001:db8:6500:100::10 -c 3 -W 1 2001:db8:6510::1
docker exec "${lab_prefix}-service" \
  ping -6 -I 2001:db8:6500:100::10 -c 3 -W 1 2001:db8:6520::1
docker exec "${lab_prefix}-transit-a" \
  ping -I 11.11.0.1 -c 3 -W 1 203.0.113.10
docker exec "${lab_prefix}-transit-b" \
  ping -6 -I 2001:db8:6520::1 -c 3 -W 1 2001:db8:6500:100::10

echo
echo "PASS: Internet Edge control plane and dual-stack forwarding are healthy."
