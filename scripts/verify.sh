#!/usr/bin/env bash
set -euo pipefail

lab_prefix="clab-internet-edge"

vtysh() {
  local node="$1"
  shift
  docker exec "${lab_prefix}-${node}" vtysh "$@"
}

bgp_session_up() {
  local node="$1"
  local family="$2"
  local peer="$3"

  vtysh "$node" -c "show bgp ${family} unicast summary" 2>/dev/null |
    awk -v peer="$peer" \
      '$1 == peer && $3 == "205013" && $10 ~ /^[0-9]+$/ { found = 1 }
       END { exit !found }'
}

gobgp_neighbor_up() {
  local node="$1"
  local peer="$2"

  docker exec "${lab_prefix}-${node}" gobgp neighbor 2>/dev/null |
    awk -v peer="$peer" \
      '$1 == peer && $4 == "Establ" { found = 1 }
       END { exit !found }'
}

echo "Waiting for IPv4 and IPv6 BGP routes..."
for attempt in $(seq 1 60); do
  if vtysh tpe10-bb-tra-t1-r1 -c "show bgp ipv4 unicast 11.11.0.0/16" 2>/dev/null |
       grep -q "1111" &&
     vtysh tpe10-bb-tra-t1-r1 -c "show bgp ipv4 unicast 22.22.0.0/16" 2>/dev/null |
       grep -q "2222" &&
     vtysh tpe10-bb-tra-t1-r2 -c "show bgp ipv4 unicast 11.11.0.0/16" 2>/dev/null |
       grep -q "1111" &&
     vtysh tpe10-bb-tra-t1-r2 -c "show bgp ipv4 unicast 22.22.0.0/16" 2>/dev/null |
       grep -q "2222" &&
     vtysh tpe10-bb-tra-t1-r1 -c "show bgp ipv6 unicast 2001:db8:6510::/48" 2>/dev/null |
       grep -q "1111" &&
     vtysh tpe10-bb-tra-t1-r1 -c "show bgp ipv6 unicast 2001:db8:6520::/48" 2>/dev/null |
       grep -q "2222" &&
     vtysh tpe10-bb-tra-t1-r2 -c "show bgp ipv6 unicast 2001:db8:6510::/48" 2>/dev/null |
       grep -q "1111" &&
     vtysh tpe10-bb-tra-t1-r2 -c "show bgp ipv6 unicast 2001:db8:6520::/48" 2>/dev/null |
       grep -q "2222" &&
     vtysh tpe10-bb-core-t1-r1 -c "show bgp ipv4 unicast 11.11.0.0/16" 2>/dev/null |
       grep -q "1111" &&
     vtysh tpe10-bb-core-t1-r1 -c "show bgp ipv4 unicast 22.22.0.0/16" 2>/dev/null |
       grep -q "2222" &&
     vtysh tpe10-bb-core-t1-r1 -c "show bgp ipv6 unicast 2001:db8:6510::/48" 2>/dev/null |
       grep -q "1111" &&
     vtysh tpe10-bb-core-t1-r1 -c "show bgp ipv6 unicast 2001:db8:6520::/48" 2>/dev/null |
       grep -q "2222" &&
     vtysh tpe10-bb-core-t1-r2 -c "show bgp ipv4 unicast 11.11.0.0/16" 2>/dev/null |
       grep -q "1111" &&
     vtysh tpe10-bb-core-t1-r2 -c "show bgp ipv4 unicast 22.22.0.0/16" 2>/dev/null |
       grep -q "2222" &&
     vtysh tpe10-bb-core-t1-r2 -c "show bgp ipv6 unicast 2001:db8:6510::/48" 2>/dev/null |
       grep -q "1111" &&
     vtysh tpe10-bb-core-t1-r2 -c "show bgp ipv6 unicast 2001:db8:6520::/48" 2>/dev/null |
       grep -q "2222"; then
    break
  fi

  if [[ "$attempt" -eq 60 ]]; then
    echo "ERROR: BGP routes did not converge within 60 seconds." >&2
    exit 1
  fi
  sleep 1
done

echo "Waiting for all redundant RR sessions..."
for attempt in $(seq 1 60); do
  all_up=true
  for client in \
    tpe10-bb-tra-t1-r1 tpe10-bb-tra-t1-r2 \
    tpe10-bb-core-t1-r1 tpe10-bb-core-t1-r2 \
    tpe10-bb-org-t1-r1 tpe10-bb-org-t1-r2; do
    for rr in 21 22; do
      bgp_session_up "$client" ipv4 "10.255.0.${rr}" || all_up=false
      bgp_session_up "$client" ipv6 "fd00:6500::${rr}" || all_up=false
    done
  done
  for node in tpe10-bb-rr-ext-r1 tpe10-bb-rr-ext-r2 tpe10-bb-core-t1-r1 tpe10-bb-core-t1-r2; do
    for t2 in 11 12; do
      bgp_session_up "$node" ipv4 "172.31.255.${t2}" || all_up=false
      bgp_session_up "$node" ipv6 "172.31.255.${t2}" || all_up=false
    done
  done
  for t2 in tpe10-bb-rr-ctrl-r1 tpe10-bb-rr-ctrl-r2; do
    for peer in 4 5 6 7; do
      gobgp_neighbor_up "$t2" "172.31.255.${peer}" || all_up=false
    done
  done

  if "$all_up"; then
    break
  fi
  if [[ "$attempt" -eq 60 ]]; then
    echo "ERROR: Not all redundant RR sessions established within 60 seconds." >&2
    exit 1
  fi
  sleep 1
done

echo "Waiting for Originator aggregates and export policies..."
for attempt in $(seq 1 60); do
  if vtysh tpe10-bb-tra-t1-r1 \
       -c "show bgp ipv4 unicast 203.0.113.0/24" 2>/dev/null |
       grep -Fq "Large Community: 205013:100:0" &&
     vtysh tpe10-bb-tra-t1-r2 \
       -c "show bgp ipv6 unicast 2001:db8:6500::/48" 2>/dev/null |
       grep -Fq "Large Community: 205013:100:0" &&
     vtysh transit-a \
       -c "show bgp ipv4 unicast 203.0.113.0/24" 2>/dev/null |
       grep -Fq "metric 50" &&
     vtysh transit-b \
       -c "show bgp ipv4 unicast 203.0.113.0/24" 2>/dev/null |
       grep -Fq "metric 150"; then
    break
  fi
  if [[ "$attempt" -eq 60 ]]; then
    echo "ERROR: Originator export policies did not converge in 60 seconds." >&2
    exit 1
  fi
  sleep 1
done

echo
echo "=== Edge IPv4 BGP summaries ==="
vtysh tpe10-bb-tra-t1-r1 -c "show bgp ipv4 unicast summary"
vtysh tpe10-bb-tra-t1-r2 -c "show bgp ipv4 unicast summary"

echo
echo "=== Edge IPv6 BGP summaries ==="
vtysh tpe10-bb-tra-t1-r1 -c "show bgp ipv6 unicast summary"
vtysh tpe10-bb-tra-t1-r2 -c "show bgp ipv6 unicast summary"

echo
echo "=== RR-EXT checks ==="
for rr in tpe10-bb-rr-ext-r1 tpe10-bb-rr-ext-r2; do
  running_config="$(vtysh "$rr" -c "show running-config")"
  grep -Fq "bgp cluster-id 10.255.255.1" <<<"$running_config"
  grep -Fq "neighbor RR-CLIENTS route-reflector-client" <<<"$running_config"
  grep -Fq "neighbor RR-CLIENTS-V6 route-reflector-client" <<<"$running_config"
  grep -Fq "addpath-tx-all-paths" <<<"$running_config"
  echo "${rr}: RR-EXT clients and ADD-PATH feeds are configured"
done

for client in \
  tpe10-bb-tra-t1-r1 tpe10-bb-tra-t1-r2 \
  tpe10-bb-core-t1-r1 tpe10-bb-core-t1-r2 \
  tpe10-bb-org-t1-r1 tpe10-bb-org-t1-r2; do
  bgp_session_up "$client" ipv4 "10.255.0.21"
  bgp_session_up "$client" ipv4 "10.255.0.22"
  bgp_session_up "$client" ipv6 "fd00:6500::21"
  bgp_session_up "$client" ipv6 "fd00:6500::22"
  echo "${client}: both RR-EXT sessions are present"
done

echo
echo "=== Prefix Originator and community checks ==="
for originator in tpe10-bb-org-t1-r1 tpe10-bb-org-t1-r2; do
  running_config="$(vtysh "$originator" -c "show running-config")"
  grep -Fq "ip route 203.0.113.0/24 Null0" <<<"$running_config"
  grep -Fq "ipv6 route 2001:db8:6500::/48 Null0" <<<"$running_config"
  grep -Fq "set large-community 205013:100:0" <<<"$running_config"
  echo "${originator}: dual-stack aggregates carry Large Community 205013:100:0"
done

for tra in tpe10-bb-tra-t1-r1 tpe10-bb-tra-t1-r2; do
  running_config="$(vtysh "$tra" -c "show running-config")"
  ipv4_owned="$(vtysh "$tra" -c \
    "show bgp ipv4 unicast 203.0.113.0/24")"
  ipv6_owned="$(vtysh "$tra" -c \
    "show bgp ipv6 unicast 2001:db8:6500::/48")"

  ! grep -Fq "ip route 203.0.113.0/24 Null0" <<<"$running_config"
  ! grep -Fq "ipv6 route 2001:db8:6500::/48 Null0" <<<"$running_config"
  ! grep -Fq "network 203.0.113.0/24" <<<"$running_config"
  ! grep -Fq "network 2001:db8:6500::/48" <<<"$running_config"
  grep -Fq "match large-community OWNED-EXPORT" <<<"$running_config"
  grep -Fq "Large Community: 205013:100:0" <<<"$ipv4_owned"
  grep -Fq "Large Community: 205013:100:0" <<<"$ipv6_owned"
  echo "${tra}: aggregate is learned from Originator and selected by community"
done

echo
echo "=== GoBGP RR-CTRL policy checks ==="
for t2 in tpe10-bb-rr-ctrl-r1 tpe10-bb-rr-ctrl-r2; do
  for peer in 4 5 6 7; do
    gobgp_neighbor_up "$t2" "172.31.255.${peer}"
  done

  policy="$(docker exec "${lab_prefix}-${t2}" gobgp policy)"
  ipv4_paths="$(docker exec "${lab_prefix}-${t2}" \
    gobgp global rib -a ipv4 0.0.0.0/0)"
  ipv6_paths="$(docker exec "${lab_prefix}-${t2}" \
    gobgp global rib -a ipv6 ::/0)"
  grep -Fq "LocalPref:  300" <<<"$policy"
  grep -Fq "10.255.0.1" <<<"$ipv4_paths"
  grep -Fq "10.255.0.2" <<<"$ipv4_paths"
  grep -Fq "LocalPref: 300" <<<"$ipv4_paths"
  grep -Fq "fd00:6500::1" <<<"$ipv6_paths"
  grep -Fq "fd00:6500::2" <<<"$ipv6_paths"
  grep -Fq "LocalPref: 300" <<<"$ipv6_paths"
  echo "${t2}: both Edge candidates received and latency baseline applied"
done

for core in tpe10-bb-core-t1-r1 tpe10-bb-core-t1-r2; do
  for t2 in 11 12; do
    bgp_session_up "$core" ipv4 "172.31.255.${t2}"
    bgp_session_up "$core" ipv6 "172.31.255.${t2}"
  done
  ipv4_route="$(vtysh "$core" -c "show bgp ipv4 unicast 22.22.0.0/16")"
  ipv6_route="$(vtysh "$core" -c \
    "show bgp ipv6 unicast 2001:db8:6520::/48")"
  grep -Eq "localpref 300,.*best" <<<"$ipv4_route"
  grep -Fq "localpref 200" <<<"$ipv4_route"
  grep -Eq "localpref 300,.*best" <<<"$ipv6_route"
  grep -Fq "localpref 200" <<<"$ipv6_route"
  echo "${core}: RR-CTRL policy path is best and RR-EXT fallback remains installed"
done

echo
echo "=== Edge BFD peers ==="
vtysh tpe10-bb-tra-t1-r1 -c "show bfd peers brief"
vtysh tpe10-bb-tra-t1-r2 -c "show bfd peers brief"

echo
echo "=== Inbound bogon policy checks ==="
for node in tpe10-bb-tra-t1-r1 tpe10-bb-tra-t1-r2; do
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
echo "=== Community-driven Transit export policy checks ==="
transit_a_v4="$(vtysh transit-a -c \
  "show bgp ipv4 unicast 203.0.113.0/24")"
transit_a_v6="$(vtysh transit-a -c \
  "show bgp ipv6 unicast 2001:db8:6500::/48")"
transit_b_v4="$(vtysh transit-b -c \
  "show bgp ipv4 unicast 203.0.113.0/24")"
transit_b_v6="$(vtysh transit-b -c \
  "show bgp ipv6 unicast 2001:db8:6500::/48")"

for route in "$transit_a_v4" "$transit_a_v6"; do
  grep -Eq "^[[:space:]]+205013 205013$" <<<"$route"
  grep -Fq "metric 50" <<<"$route"
  ! grep -Fq "Large Community:" <<<"$route"
done
for route in "$transit_b_v4" "$transit_b_v6"; do
  grep -Eq "^[[:space:]]+205013 205013 205013 205013$" <<<"$route"
  grep -Fq "metric 150" <<<"$route"
  ! grep -Fq "Large Community:" <<<"$route"
done
echo "Transit-A uses prepend 1/MED 50; Transit-B uses prepend 3/MED 150"

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
echo "PASS: Originator, RR-EXT/RR-CTRL policies, and dual-stack forwarding are healthy."
