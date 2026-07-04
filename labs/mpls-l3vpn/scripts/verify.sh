#!/usr/bin/env bash
set -euo pipefail

lab_prefix="clab-mpls-l3vpn"

vtysh() {
  local node="$1"
  shift
  docker exec "${lab_prefix}-${node}" vtysh "$@"
}

route_is_installed() {
  local pe="$1"
  local vrf="$2"
  local prefix="$3"

  vtysh "$pe" -c "show ip route vrf ${vrf}" 2>/dev/null |
    grep -Eq "B[>*[:space:]]+${prefix}"
}

echo "Waiting for LDP, VPNv4, and customer routes..."
for attempt in $(seq 1 60); do
  if vtysh tpe10-svc-pe-t1-r1 -c "show mpls ldp neighbor" 2>/dev/null |
       grep -Fq "10.255.100.2" &&
     vtysh tpe10-svc-p-t1-r1 -c "show mpls ldp neighbor" 2>/dev/null |
       grep -Fq "10.255.100.1" &&
     vtysh tpe10-svc-p-t1-r1 -c "show mpls ldp neighbor" 2>/dev/null |
       grep -Fq "10.255.100.3" &&
     vtysh tpe10-svc-pe-t1-r2 -c "show mpls ldp neighbor" 2>/dev/null |
       grep -Fq "10.255.100.2" &&
     route_is_installed tpe10-svc-pe-t1-r1 BLUE 192.0.2.4/30 &&
     route_is_installed tpe10-svc-pe-t1-r1 GREEN 192.0.2.4/30 &&
     route_is_installed tpe10-svc-pe-t1-r2 BLUE 192.0.2.0/30 &&
     route_is_installed tpe10-svc-pe-t1-r2 GREEN 192.0.2.0/30; then
    break
  fi

  if [[ "$attempt" -eq 60 ]]; then
    echo "ERROR: MPLS L3VPN did not converge within 60 seconds." >&2
    exit 1
  fi
  sleep 1
done

echo "Checking route distinguishers and route-target isolation..."
vpn_rib="$(vtysh tpe10-svc-pe-t1-r1 -c "show bgp ipv4 vpn")"
for rd in 205013:1001 205013:1002 205013:2001 205013:2002; do
  grep -Fq "Route Distinguisher: ${rd}" <<<"$vpn_rib"
done

pe1_config="$(vtysh tpe10-svc-pe-t1-r1 -c "show running-config")"
grep -Fq "rt vpn both 205013:100" <<<"$pe1_config"
grep -Fq "rt vpn both 205013:200" <<<"$pe1_config"

global_routes="$(vtysh tpe10-svc-pe-t1-r1 -c "show ip route")"
if grep -Fq "192.0.2." <<<"$global_routes"; then
  echo "ERROR: A customer prefix leaked into the provider global table." >&2
  exit 1
fi

echo "Checking MPLS transport and VPN labels..."
grep -Fq "LDP" <<<"$(vtysh tpe10-svc-p-t1-r1 -c "show mpls table")"
grep -Fq "BGP" <<<"$(vtysh tpe10-svc-pe-t1-r1 -c "show mpls table")"

echo "Checking BLUE and GREEN forwarding with overlapping addresses..."
docker exec "${lab_prefix}-ce-blue-a" \
  ping -I 192.0.2.2 -c 3 -W 1 192.0.2.6 >/dev/null
docker exec "${lab_prefix}-ce-blue-b" \
  ping -I 192.0.2.6 -c 3 -W 1 192.0.2.2 >/dev/null
docker exec "${lab_prefix}-ce-green-a" \
  ping -I 192.0.2.2 -c 3 -W 1 192.0.2.6 >/dev/null
docker exec "${lab_prefix}-ce-green-b" \
  ping -I 192.0.2.6 -c 3 -W 1 192.0.2.2 >/dev/null

echo "PASS: MPLS transport, VPNv4 routes, VRF isolation, and CE forwarding are healthy."
