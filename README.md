# JWS

Jess Web Services

# ISP Lab — Internet Edge

這是 ISP lab 的第一階段：以 Containerlab 與 FRRouting 建立可實際驗證的
dual-stack Internet Edge。

## 目標架構

```text
             AS1111 Peer-1         Peer-2 AS2222
                     |              |
                   edge1          edge2          AS205013
                    |\              /|
                    | core1----core2 |
                    |  |\      /|    |
                    | rr1      rr2   |
                    |    \    /      |
                    |     service    |
```

實際線路是：

- `edge1` 只連 Peer-1（Transit-A）；`edge2` 只連 Peer-2（Transit-B）。
- Edge Router 與 Route Reflector 是不同機器；`edge1`、`edge2` 不再兼任 RR。
- Edge 與 Core 間有四條 uplink；Core 彼此互連。
- `service` 雙歸到兩台 Core，用來做真正的端到端測試。
- `rr1`、`rr2` 各自雙歸到兩台 Core，避免單一 Core 或單一 RR 成為控制平面
  的單點故障。
- AS205013 內跑 OSPFv2/OSPFv3。`rr1`、`rr2` 是共用 cluster ID
  `10.255.255.1` 的獨立冗餘 Route Reflectors；`edge1`、`edge2`、`core1`
  與 `core2` 都同時是兩台 RR 的 clients。
- 每台 Edge 與各自的 Transit 建立 IPv4/IPv6 eBGP，並以 BFD 偵測故障。

AS1111、AS2222、`11.11.0.0/16` 與 `22.22.0.0/16` 在此僅供隔離 lab
模擬；未取得相應授權時不得公告至真實 Internet。其餘 IPv4/IPv6 位址為
private 或文件專用值。

## 已實作的 Edge policy

- AS205013 只對外公告 `203.0.113.0/24` 與 `2001:db8:6500::/48`。
- Prefix-list 阻止其他內部路由外洩。
- Inbound prefix-list 只接受本 lab 的 default 與模擬 Internet prefixes。
- Inbound policy 明確拒絕 RFC1918、IPv6 ULA，以及含 RFC 6996 Private ASN
  的 AS_PATH。
- 每個 eBGP address-family 設定 maximum-prefix。
- `edge1` 使用 Peer-1；`edge2` 使用 Peer-2，並透過獨立的雙 RR 架構交換
  外部路由。
- RR 與 clients 都使用 loopback 建立 iBGP，底層由雙核心 OSPF 提供可達性。
- Edge 對外的 outbound prefix-list 只允許 AS205013 自有 aggregate，因此
  Peer-1 學不到 Peer-2 prefix，Peer-2 也學不到 Peer-1 prefix；AS205013
  不提供兩個外部 Peer 之間的 transit。

## Windows 前置環境

Containerlab 需要 Linux。Windows 官方做法是 WSL2；目前這台機器尚未安裝
WSL distribution，Docker daemon 也沒有運作。

在系統管理員 PowerShell 執行：

```powershell
wsl --install
```

重新開機後，可安裝 Containerlab 官方提供的 WSL-Containerlab distribution，
或在 Ubuntu WSL 內安裝 Docker 與 Containerlab：

```bash
sudo apt update
sudo apt -y install curl
curl -sL https://containerlab.dev/setup | sudo -E bash -s "all"
newgrp docker
```

若使用 Docker Desktop，請依 Containerlab 官方 Windows 指南關閉該 WSL
distribution 的 Docker Desktop integration；Containerlab 建議在 WSL VM
內使用原生 Docker Engine。

## 啟動與驗證

在 WSL shell 進入本目錄。Windows 的 `C:\Users\jessyu\Documents\JWS lab`
通常會掛載為：

```bash
cd "/mnt/c/Users/jessyu/Documents/JWS lab"
sudo containerlab deploy --topo internet-edge.clab.yml
bash scripts/verify.sh
```

也可以使用相同操作的快捷命令：`make deploy`、`make verify`。若要實際中斷
`rr1` 驗證 HA，再執行 `make verify-ha`；腳本結束時會自動重新啟動 `rr1`。

驗證腳本會檢查：

1. IPv4/IPv6 BGP 路由是否在 60 秒內收斂。
2. Edge BGP summary 與 BFD peers。
3. Edge/Core 到兩台獨立 RR 的 IPv4/IPv6 client sessions。
4. Peer-1/Peer-2 彼此的 IPv4/IPv6 prefix 沒有外洩，且不能經 AS205013
   互通。
5. service 到兩個 Transit loopback 的雙向 IPv4/IPv6 forwarding。
6. Transit 到 AS205013 service prefix 的回程 forwarding。

`make verify-ha` 會暫停 `rr1`，確認 `rr2` 單獨運作時，兩台 Edge 仍保有
彼此的 IPv4/IPv6 Transit 路由，且 service forwarding 不受影響。

進入 FRR CLI：

```bash
docker exec -it clab-internet-edge-edge1 vtysh
docker exec -it clab-internet-edge-rr1 vtysh
```

常用命令：

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

## 故障切換練習

先驗證 Route Reflector HA：

```bash
make verify-ha
```

也可以觀察 `edge1` 對 Transit-A 的路由，再中斷該 circuit：

```bash
docker exec clab-internet-edge-edge1 \
  vtysh -c "show bgp ipv4 unicast 11.11.0.0/16"
docker exec clab-internet-edge-edge1 ip link set eth3 down
sleep 3
docker exec clab-internet-edge-edge1 \
  vtysh -c "show bgp ipv4 unicast 11.11.0.0/16"
bash scripts/verify.sh
docker exec clab-internet-edge-edge1 ip link set eth3 up
```

失效後，Transit-A 專屬的 `11.11.0.0/16` 會中斷；Transit-B 與內部 iBGP
應維持正常。此一對一接法刻意不提供單一 Transit circuit 的備援。

清除 lab：

```bash
sudo containerlab destroy --cleanup --topo internet-edge.clab.yml
```

快捷命令為 `make destroy`。

## 位址與 AS 摘要

| 用途 | 值 |
|---|---|
| ISP | AS205013 |
| Transit-A | AS1111 |
| Transit-B | AS2222 |
| ISP IPv4 aggregate | `203.0.113.0/24` |
| ISP IPv6 aggregate | `2001:db8:6500::/48` |
| Transit-A simulated Internet | `11.11.0.0/16`, `2001:db8:6510::/48` |
| Transit-B simulated Internet | `22.22.0.0/16`, `2001:db8:6520::/48` |
| IPv4 IGP loopbacks | `10.255.0.0/24` |
| IPv6 IGP loopbacks | `fd00:6500::/48` |
| RR1 loopbacks | `10.255.0.21/32`, `fd00:6500::21/128` |
| RR2 loopbacks | `10.255.0.22/32`, `fd00:6500::22/128` |

Containerlab topology 與 bind mount 的寫法依官方文件；FRR image 固定在
`quay.io/frrouting/frr:10.6.1`，避免 `latest` 漂移。
