# JWS

Jess Web Services

# ISP Lab — Internet Edge

這是 ISP lab 的第一階段：以 Containerlab 與 FRRouting 建立可實際驗證的
dual-stack Internet Edge。

## 目標架構

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

命名格式為
`<location-code>-<network-segment>-<device-function>-<tier-number>-<router-number>`：

| 舊名稱 | 新名稱 |
|---|---|
| `edge1`, `edge2` | `tpe10-bb-tra-t1-r1`, `tpe10-bb-tra-t1-r2` |
| `core1`, `core2` | `tpe10-bb-core-t1-r1`, `tpe10-bb-core-t1-r2` |
| `rr1`, `rr2` | `tpe10-bb-rr-ext-r1`, `tpe10-bb-rr-ext-r2` |
| `rr-t2-1`, `rr-t2-2` | `tpe10-bb-rr-ctrl-r1`, `tpe10-bb-rr-ctrl-r2` |

實際線路是：

- `tpe10-bb-tra-t1-r1` 只連 Peer-1（Transit-A）；
  `tpe10-bb-tra-t1-r2` 只連 Peer-2（Transit-B）。
- Edge Router 與 Route Reflector 是不同機器；兩台 `tra` 不兼任 RR。
- Edge 與 Core 間有四條 uplink；Core 彼此互連。
- `service` 雙歸到兩台 Core，用來做真正的端到端測試。
- `tpe10-bb-org-t1-r1`、`tpe10-bb-org-t1-r2` 是雙歸、HA 的 Prefix
  Originators，負責產生自有 aggregates；`bb-tra` 不再配置 aggregate
  Null0 或 `network`。
- `tpe10-bb-rr-ext-r1`、`tpe10-bb-rr-ext-r2` 是 RR-T1，各自雙歸到兩台
  Core，並以 ADD-PATH 將所有 Edge 候選路徑送給 RR-T2。
- `tpe10-bb-rr-ctrl-r1`、`tpe10-bb-rr-ctrl-r2` 是獨立的 GoBGP RR-T2
  policy tier，透過專用 management control network 與 T1/Core 建立
  iBGP，本身沒有 data-plane interface。
- AS205013 內跑 OSPFv2/OSPFv3。T1 共用 cluster ID `10.255.255.1`；
  T2 共用另一個 cluster ID `10.255.255.2`，避免階層式 reflection loop。
- Edge 與 Core 同時保留兩條 T1 sessions；Core 另有兩條 T2 sessions。
  T2 policy route 使用 `LOCAL_PREF 300`，T1 baseline 使用 `200`，所以兩台
  T2 都失效時，Core 會自動 fail open 回 T1。
- 每台 Edge 與各自的 Transit 建立 IPv4/IPv6 eBGP，並以 BFD 偵測故障。

AS1111、AS2222、`11.11.0.0/16` 與 `22.22.0.0/16` 在此僅供隔離 lab
模擬；未取得相應授權時不得公告至真實 Internet。其餘 IPv4/IPv6 位址為
private 或文件專用值。

## 已實作的 Edge policy

- AS205013 只對外公告 `203.0.113.0/24` 與 `2001:db8:6500::/48`。
- 兩台 Originator 以 Null0 建立 aggregates，並附加 Large Community
  `205013:100:0`（function `100` 表示允許對 Transit export）。
- `tpe10-bb-tra-t1-r1` 只有在 community match 時才向 Transit-A 公告，
  額外 prepend AS205013 一次並設定 MED 50。
- `tpe10-bb-tra-t1-r2` 額外 prepend AS205013 三次並設定 MED 150；內部
  Large Community 在 eBGP export 時移除。
- Prefix-list 阻止其他內部路由外洩。
- Inbound prefix-list 只接受本 lab 的 default 與模擬 Internet prefixes。
- Inbound policy 明確拒絕 RFC1918、IPv6 ULA，以及含 RFC 6996 Private ASN
  的 AS_PATH。
- 每個 eBGP address-family 設定 maximum-prefix。
- `tpe10-bb-tra-t1-r1` 使用 Peer-1；`tpe10-bb-tra-t1-r2` 使用 Peer-2，並透過雙層、各自 HA 的 RR
  架構交換外部路由。
- T1 與 Edge/Core 使用 loopback iBGP；T1/T2/Core 的 policy sessions
  使用固定的 `172.31.255.0/24` control network。
- T1 對 T2 啟用 ADD-PATH，因此 GoBGP 可以同時看到來自兩台 `tra` 的候選
  路徑；T2 保留 Edge loopback 作為 next hop，不承載客戶流量。
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
`tpe10-bb-rr-ext-r1` 驗證 T1 HA，執行 `make verify-ha`；若要驗證 T2 HA
與全 T2 失效時的 T1 fallback，執行 `make verify-t2-ha`。測試腳本結束會
自動重啟節點。`make verify-originator-ha` 會停止第一台 Originator，確認
另一台持續產生 aggregate。

驗證腳本會檢查：

1. IPv4/IPv6 BGP 路由是否在 60 秒內收斂。
2. Edge BGP summary 與 BFD peers。
3. Edge/Core/Originator 到 T1，以及 T1/T2/Core policy tier 的所有
   sessions。
4. Aggregate 是否只由 Originator 產生並帶有 `205013:100:0`。
5. Transit-A/B 是否分別收到預期的 AS_PATH、MED，且不含內部 community。
6. T2 是否收到兩個 Edge 的 ADD-PATH candidates、套用 `LOCAL_PREF 300`，
   且 Core 是否仍保有 `LOCAL_PREF 200` 的 T1 fallback。
7. Peer-1/Peer-2 彼此的 IPv4/IPv6 prefix 沒有外洩，且不能經 AS205013
   互通。
8. service 到兩個 Transit loopback 的雙向 IPv4/IPv6 forwarding。
9. Transit 到 AS205013 service prefix 的回程 forwarding。

`make verify-ha` 會暫停 `tpe10-bb-rr-ext-r1`，確認
`tpe10-bb-rr-ext-r2` 單獨運作時，兩台 Edge 仍保有彼此的 IPv4/IPv6
Transit 路由，且 service forwarding 不受影響。

`make verify-t2-ha` 先暫停 `tpe10-bb-rr-ctrl-r1`，確認另一台 T2 保持
policy route；再暫停 `tpe10-bb-rr-ctrl-r2`，確認 Core best path 從
`LOCAL_PREF 300` 自動降回 T1 的 `LOCAL_PREF 200`，且 forwarding
全程不中斷。

`make verify-originator-ha` 會暫停 `tpe10-bb-org-t1-r1`，確認兩台
`bb-tra` 改用 `tpe10-bb-org-t1-r2`，並保持 community-driven export
policy 與雙棧 forwarding。

進入 FRR CLI：

```bash
docker exec -it clab-internet-edge-tpe10-bb-tra-t1-r1 vtysh
docker exec -it clab-internet-edge-tpe10-bb-org-t1-r1 vtysh
docker exec -it clab-internet-edge-tpe10-bb-rr-ext-r1 vtysh
docker exec -it clab-internet-edge-tpe10-bb-rr-ctrl-r1 gobgp neighbor
docker exec -it clab-internet-edge-tpe10-bb-rr-ctrl-r1 \
  gobgp global rib -a ipv4
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
make verify-t2-ha
make verify-originator-ha
```

也可以觀察 `tpe10-bb-tra-t1-r1` 對 Transit-A 的路由，再中斷該 circuit：

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
| `tpe10-bb-rr-ext-r1` loopbacks | `10.255.0.21/32`, `fd00:6500::21/128` |
| `tpe10-bb-rr-ext-r2` loopbacks | `10.255.0.22/32`, `fd00:6500::22/128` |
| `tpe10-bb-org-t1-r1` loopbacks | `10.255.0.41/32`, `fd00:6500::41/128` |
| `tpe10-bb-org-t1-r2` loopbacks | `10.255.0.42/32`, `fd00:6500::42/128` |
| Owned-prefix Large Community | `205013:100:0` |
| T1 cluster ID | `10.255.255.1` |
| T2 cluster ID | `10.255.255.2` |
| T1/T2 control network | `172.31.255.0/24` |
| `tpe10-bb-rr-ctrl-r1` router ID / control IP | `10.255.0.31`, `172.31.255.11` |
| `tpe10-bb-rr-ctrl-r2` router ID / control IP | `10.255.0.32`, `172.31.255.12` |

Containerlab topology 與 bind mount 的寫法依官方文件；FRR image 固定在
`quay.io/frrouting/frr:10.6.1`，GoBGP image 固定在
`jauderho/gobgp:v4.5.0`，避免 `latest` 漂移。目前 `LATENCY-BASELINE`
policy 是供 latency controller 動態更新前的安全基線：T2 統一設為
`LOCAL_PREF 300`，實際量測與 hysteresis 邏輯可再透過 GoBGP gRPC API
加入。
