# JWS

Jess Web Services

# ISP Lab — Internet Edge

This is the first phase of the ISP lab: building a fully testable dual-stack Internet Edge using Containerlab and FRRouting.

## Target Architecture

```text
 AS1111 Peer-1                       Peer-2 AS2222
       |                                  |
 tpe10-bb-tra-t1-r1               tpe10-bb-tra-t1-r2
       |\                              /|
       | tpe10-bb-core-t1-r1--tpe10-bb-core-t1-r2
       |       |                 |      |
       | tpe10-bb-rr-ext-r1  tpe10-bb-rr-ext-r2
       |          \            /        |
       |   tpe10-bb-rr-ctrl-r1/r2       |
       |   tpe10-bb-org-t1-r1/r2        |
       |              |                 |
       |           service              |
```

The naming convention is:

`<location-code>-<network-segment>-<device-function>-<tier-or-role>-<router-number>`

| Role                          | Nodes                                        |
| ----------------------------- | -------------------------------------------- |
| Transit Edge (`tra`)          | `tpe10-bb-tra-t1-r1`, `tpe10-bb-tra-t1-r2`   |
| Backbone Core (`core`)        | `tpe10-bb-core-t1-r1`, `tpe10-bb-core-t1-r2` |
| External-route RR (`rr-ext`)  | `tpe10-bb-rr-ext-r1`, `tpe10-bb-rr-ext-r2`   |
| Policy-control RR (`rr-ctrl`) | `tpe10-bb-rr-ctrl-r1`, `tpe10-bb-rr-ctrl-r2` |
| Prefix Originator (`org`)     | `tpe10-bb-org-t1-r1`, `tpe10-bb-org-t1-r2`   |

The physical and logical connectivity is as follows:

* `tpe10-bb-tra-t1-r1` connects only to Peer-1, or Transit-A, while
  `tpe10-bb-tra-t1-r2` connects only to Peer-2, or Transit-B.
* The Edge Routers and Route Reflectors are separate devices. The two `tra`
  routers do not also act as RRs.
* There are four uplinks between the Edge and Core layers, and the two Core
  routers are interconnected.
* The `service` node is dual-homed to both Core routers and is used for actual
  end-to-end testing.
* `tpe10-bb-org-t1-r1` and `tpe10-bb-org-t1-r2` are dual-homed, highly
  available Prefix Originators responsible for originating the ISP-owned
  aggregates. Aggregate Null0 routes and BGP `network` statements are no
  longer configured on the `bb-tra` routers.
* `tpe10-bb-rr-ext-r1` and `tpe10-bb-rr-ext-r2` are the RR-EXT nodes. Each is
  dual-homed to both Core routers and uses ADD-PATH to advertise all candidate
  Edge paths to the RR-CTRL layer.
* `tpe10-bb-rr-ctrl-r1` and `tpe10-bb-rr-ctrl-r2` are independent GoBGP
  RR-CTRL nodes. They establish iBGP sessions with RR-EXT and the Core routers
  over a dedicated management control network and do not have data-plane
  interfaces.
* AS205013 runs OSPFv2 and OSPFv3 internally. The RR-EXT nodes share cluster ID
  `10.255.255.1`, while the RR-CTRL nodes share a separate cluster ID,
  `10.255.255.2`, to prevent hierarchical route-reflection loops.
* Each Edge and Core router maintains sessions with both RR-EXT nodes. Each
  Core router also maintains sessions with both RR-CTRL nodes. RR-CTRL policy
  routes use `LOCAL_PREF 300`, while the RR-EXT baseline uses `LOCAL_PREF 200`.
  Therefore, if both RR-CTRL nodes fail, the Core routers automatically fail
  open to the RR-EXT routes.
* Each Edge router establishes IPv4 and IPv6 eBGP sessions with its associated
  Transit provider and uses BFD for failure detection.

AS1111, AS2222, `11.11.0.0/16`, and `22.22.0.0/16` are used only for isolated
lab simulation. They must not be advertised to the real Internet without the
appropriate authorization. All remaining IPv4 and IPv6 addresses are either
private or documentation-only values.

## Implemented Edge Policies

* AS205013 advertises only `203.0.113.0/24` and `2001:db8:6500::/48` to
  external peers.
* Both Originators install the aggregates through Null0 routes and attach Large
  Community `205013:100:0`, where function `100` means that export to Transit
  providers is permitted.
* `tpe10-bb-tra-t1-r1` advertises a prefix to Transit-A only when the community
  matches. It additionally prepends AS205013 once and sets MED to 50.
* `tpe10-bb-tra-t1-r2` prepends AS205013 three additional times and sets MED
  to 150. Internal Large Communities are removed during eBGP export.
* Prefix lists prevent other internal routes from leaking externally.
* Inbound prefix lists accept only the lab default routes and simulated
  Internet prefixes.
* Inbound policies explicitly reject RFC1918 prefixes, IPv6 ULA prefixes, and
  routes whose AS_PATH contains RFC 6996 private ASNs.
* A maximum-prefix limit is configured for every eBGP address family.
* `tpe10-bb-tra-t1-r1` uses Peer-1, while `tpe10-bb-tra-t1-r2` uses Peer-2.
  External routes are exchanged internally through a two-layer, independently
  highly available RR architecture.
* RR-EXT uses loopback-based iBGP sessions with the Edge, Core, and Originator
  routers. The policy sessions between RR-EXT, RR-CTRL, and the Core routers
  use the dedicated `172.31.255.0/24` control network.
* ADD-PATH is enabled from RR-EXT to RR-CTRL, allowing GoBGP to see candidate
  paths from both `tra` routers simultaneously. RR-CTRL preserves the Edge
  loopback as the BGP next hop and does not carry customer traffic.
* The outbound prefix lists on the Edge routers permit only AS205013-owned
  aggregates. Therefore, Peer-1 does not learn Peer-2 prefixes, and Peer-2
  does not learn Peer-1 prefixes. AS205013 does not provide transit between
  the two external peers.

## Windows Prerequisites

Containerlab requires Linux. On Windows, the officially supported approach is
WSL2. This machine currently does not have a WSL distribution installed, and
the Docker daemon is not running.

Run the following command in an elevated PowerShell session:

```powershell
wsl --install
```

After rebooting, either install the official WSL-Containerlab distribution
provided by Containerlab, or install Docker and Containerlab inside an Ubuntu
WSL distribution:

```bash
sudo apt update
sudo apt -y install curl
curl -sL https://containerlab.dev/setup | sudo -E bash -s "all"
newgrp docker
```

When using Docker Desktop, disable Docker Desktop integration for the WSL
distribution according to the official Containerlab Windows guide.
Containerlab recommends using a native Docker Engine inside the WSL VM.

## Deployment and Verification

Open a WSL shell and change to this directory. The Windows directory
`C:\Users\jessyu\Documents\JWS lab` is typically mounted as:

```bash
cd "/mnt/c/Users/jessyu/Documents/JWS lab"
sudo containerlab deploy --topo internet-edge.clab.yml
bash scripts/verify.sh
```

The equivalent shortcut commands are `make deploy` and `make verify`.

To stop `tpe10-bb-rr-ext-r1` and validate RR-EXT high availability, run
`make verify-ext-ha`.

To validate RR-CTRL high availability and RR-EXT fallback when all RR-CTRL
nodes have failed, run `make verify-ctrl-ha`.

The test scripts automatically restart the affected nodes when the tests
finish.

`make verify-originator-ha` stops the first Originator and confirms that the
second Originator continues to originate the aggregates.

The verification script checks the following:

1. Whether IPv4 and IPv6 BGP routes converge within 60 seconds.
2. Edge BGP summaries and BFD peers.
3. All sessions from the Edge, Core, and Originator routers to RR-EXT, as well
   as all sessions in the RR-EXT, RR-CTRL, and Core policy plane.
4. Whether the aggregates are originated only by the Originators and carry
   Large Community `205013:100:0`.
5. Whether Transit-A and Transit-B receive the expected AS_PATH and MED values,
   without internal communities.
6. Whether RR-CTRL receives ADD-PATH candidates from both Edge routers and
   applies `LOCAL_PREF 300`, while the Core routers retain the RR-EXT fallback
   paths with `LOCAL_PREF 200`.
7. Whether the IPv4 and IPv6 prefixes belonging to Peer-1 and Peer-2 remain
   isolated and cannot reach each other through AS205013.
8. Bidirectional IPv4 and IPv6 forwarding between the `service` node and both
   Transit loopbacks.
9. Return-path forwarding from the Transit networks to the AS205013 service
   prefix.

`make verify-ext-ha` pauses `tpe10-bb-rr-ext-r1` and confirms that, while
`tpe10-bb-rr-ext-r2` operates alone, both Edge routers retain each other's
IPv4 and IPv6 Transit routes and service forwarding remains unaffected.

`make verify-ctrl-ha` first pauses `tpe10-bb-rr-ctrl-r1` and confirms that the
remaining RR-CTRL continues to provide the policy route. It then pauses
`tpe10-bb-rr-ctrl-r2` and verifies that the Core best path automatically falls
back from the RR-CTRL route with `LOCAL_PREF 300` to the RR-EXT route with
`LOCAL_PREF 200`, without interrupting forwarding.

`make verify-originator-ha` pauses `tpe10-bb-org-t1-r1` and confirms that both
`bb-tra` routers switch to `tpe10-bb-org-t1-r2` while preserving the
community-driven export policy and dual-stack forwarding.

Enter the FRR CLI:

```bash
docker exec -it clab-internet-edge-tpe10-bb-tra-t1-r1 vtysh
docker exec -it clab-internet-edge-tpe10-bb-org-t1-r1 vtysh
docker exec -it clab-internet-edge-tpe10-bb-rr-ext-r1 vtysh
docker exec -it clab-internet-edge-tpe10-bb-rr-ctrl-r1 gobgp neighbor
docker exec -it clab-internet-edge-tpe10-bb-rr-ctrl-r1 \
  gobgp global rib -a ipv4
```

Common commands:

```text
show ip ospf neighbor
show ipv6 ospf6 neighbor
show bgp ipv4 unicast summary
show bgp ipv6 unicast summary
show bgp ipv4 unicast
show bfd peers brief
show ip route
show ipv6 route
```

## Failover Exercises

First, validate Route Reflector high availability:

```bash
make verify-ext-ha
make verify-ctrl-ha
make verify-originator-ha
```

You can also inspect the route from `tpe10-bb-tra-t1-r1` toward Transit-A and
then interrupt the circuit:

```bash
docker exec clab-internet-edge-tpe10-bb-tra-t1-r1 \
  vtysh -c "show bgp ipv4 unicast 11.11.0.0/16"
docker exec clab-internet-edge-tpe10-bb-tra-t1-r1 ip link set eth3 down
sleep 3
docker exec clab-internet-edge-tpe10-bb-tra-t1-r1 \
  vtysh -c "show bgp ipv4 unicast 11.11.0.0/16"
bash scripts/verify.sh
docker exec clab-internet-edge-tpe10-bb-tra-t1-r1 ip link set eth3 up
```

After the failure, the Transit-A-specific `11.11.0.0/16` prefix becomes
unreachable. Transit-B and internal iBGP should remain operational. This
one-to-one connectivity model intentionally does not provide redundancy for
an individual Transit circuit.

Destroy the lab:

```bash
sudo containerlab destroy --cleanup --topo internet-edge.clab.yml
```

The shortcut command is `make destroy`.

## Addressing and AS Summary

| Purpose                                      | Value                                 |
| -------------------------------------------- | ------------------------------------- |
| ISP                                          | AS205013                              |
| Transit-A                                    | AS1111                                |
| Transit-B                                    | AS2222                                |
| ISP IPv4 aggregate                           | `203.0.113.0/24`                      |
| ISP IPv6 aggregate                           | `2001:db8:6500::/48`                  |
| Transit-A simulated Internet                 | `11.11.0.0/16`, `2001:db8:6510::/48`  |
| Transit-B simulated Internet                 | `22.22.0.0/16`, `2001:db8:6520::/48`  |
| IPv4 IGP loopbacks                           | `10.255.0.0/24`                       |
| IPv6 IGP loopbacks                           | `fd00:6500::/48`                      |
| `tpe10-bb-rr-ext-r1` loopbacks               | `10.255.0.21/32`, `fd00:6500::21/128` |
| `tpe10-bb-rr-ext-r2` loopbacks               | `10.255.0.22/32`, `fd00:6500::22/128` |
| `tpe10-bb-org-t1-r1` loopbacks               | `10.255.0.41/32`, `fd00:6500::41/128` |
| `tpe10-bb-org-t1-r2` loopbacks               | `10.255.0.42/32`, `fd00:6500::42/128` |
| Owned-prefix Large Community                 | `205013:100:0`                        |
| RR-EXT cluster ID                            | `10.255.255.1`                        |
| RR-CTRL cluster ID                           | `10.255.255.2`                        |
| RR-EXT/RR-CTRL control network               | `172.31.255.0/24`                     |
| `tpe10-bb-rr-ctrl-r1` router ID / control IP | `10.255.0.31`, `172.31.255.11`        |
| `tpe10-bb-rr-ctrl-r2` router ID / control IP | `10.255.0.32`, `172.31.255.12`        |

The Containerlab topology and bind-mount syntax follow the official
documentation. The FRR image is pinned to
`quay.io/frrouting/frr:10.6.1`, and the GoBGP image is pinned to
`jauderho/gobgp:v4.5.0`, preventing unexpected changes caused by a moving
`latest` tag.

The current `LATENCY-BASELINE` policy serves as a safe baseline before dynamic
updates from the latency controller are introduced. RR-CTRL uniformly assigns
`LOCAL_PREF 300`. Actual latency measurements and hysteresis logic can be
added later through the GoBGP gRPC API.