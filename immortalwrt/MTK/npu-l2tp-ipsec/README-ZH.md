# R4：L2TPv2 / IPsec 与策略路由

此入口随本项目 25.12 固件安装，默认关闭。支持 UniFi/UCG L2TP 服务和可选的 Linux 对端模板。
IKE 负责建立 IPsec SA，EIP197 处理 ESP，NPU 处理 L2TP，PPE 处理可卸载的内层转发。
PassWall/OpenClash 本机核心的规则、TLS、Reality、Shadowsocks 等处理仍由 CPU 执行。

## 固件与出口

使用包含 `crypto-eip-inline`、PCE、`npu-nf_hnat`、xl2tpd、strongSwan 和 nft-xfrm 的完整 25.12 镜像。
该 EIP 驱动与 SafeXcel 争用同一硬件，本构建选择 inline 驱动。当前 24.10 移植仍拒绝联合 CDRT 路径。
不要把其他固件或内核编译的 `.ko` 安装到当前系统。

支持直接 MT7988 GMAC，或一个直连、处于 forwarding 状态、关闭 VLAN filtering 的 WAN 桥。
多端口桥、叠加 VLAN/PPPoE/DSA 的联合卸载尚未通过此入口适配，驱动会拒绝分配上下文。
控制器使用现有 `lan` / `wan` 防火墙区域、表 201、规则优先级 8990–9032、IPsec reqid 4242。
这些编号需要空闲；已有同名配置不会被覆盖。

## 1. 准备对端

### UniFi UCG / Cloud Gateway Fiber

官方规格列出 L2TP VPN Server 支持：
https://techspecs.ui.com/unifi/cloud-gateways/ucg-fiber
官方 L2TP 说明：
https://help.ui.com/hc/en-us/articles/12594825307927-UniFi-Gateway-L2TP-VPN-Server

在 UniFi Network 的 VPN / VPN Server 中启用 L2TP，配置独立、不重叠的 VPN 地址池，
例如 `10.77.0.1/24`，并创建 R4 专用 PPP 用户。PSK 与用户名/密码仅在本机填写。
使用现有 PSK 时无需改成十六进制；控制器会保留其原始字节，不会把密钥写进日志。

在 R4 先执行（替换示例对端 IP）：

```sh
mtk-npu-tunnel profile-unifi 203.0.113.10
```

此命令仅保存 IKEv1 兼容参数、自动本端身份和远端 `%any` 身份匹配，保留已有凭据与目标列表。
算法先给出 SHA256 及 SHA1 的 AES / DH14 兼容集合；以实际 SA 协商结果为准。
若协商不一致，依据日志调整 `ike_proposals` / `esp_proposals`，不需要重编固件。
UCG 的 VPN 防火墙要允许 VPN 客户端访问测试 LAN；需要经 UCG 上网时，再核对 VPN → External 转发与 NAT。

如果 UCG 是 R4 的同一上级，连接其公网地址仍在上级本机终止；要核对它的 LAN 侧 IKE 监听与
Internal → Gateway 防火墙策略。若 VPN 服务也接受 LAN 地址，可改用上级 LAN 地址，减少公网地址的干扰。
此时用另一台 Mac 接 R4、Windows 服务端接 UCG LAN，选择 Windows `/32` 作为首个策略目标。
L2TP 不会向客户端推送分流路由，下面的表 201 与目标规则负责这一步。

### Linux 对端（可选）

Linux 对端安装 strongSwan swanctl、xl2tpd、ppp 和内核 L2TP/PPP 支持。
将 `peer-linux` 的三个 example 文件按注释放入相应目录，替换公网 IP、PSK。
双方填写相同的 PSK 文本；新建密钥可用 `openssl rand -hex 32` 生成，不加 `0x`。
在对端 `/etc/ppp/chap-secrets` 添加 PPP 登录（替换用户名与密码）：

```text
"r4user" npu-lns "REPLACE_WITH_PPP_PASSWORD" *
```

设置这些配置和凭据文件仅 root 可读。允许 UDP 500/4500、ESP 及已解密的 UDP 1701。
UDP 1701 仅允许 `ipsec in reqid 4242`，其余明文请求丢弃；保持原有防火墙其他规则。
开启对端 IPv4 转发，允许 PPP 接口向公网出口转发及回包。
如果需要经对端访问互联网，为 `10.77.0.0/24` 在实际公网出口配置 SNAT/masquerade。
已有 L2TP/IPsec 服务可以直接使用，无需覆盖其全局配置；须对齐 IKE 版本、身份和 ESP 算法。
此模板用 IKEv2、IKE aes256-sha256-modp2048、ESP aes128-sha256，允许 IPsec transport 模式。
RouterOS 内置 L2TP/IPsec 常用 IKEv1，可设置 `ike_version=1` 并按对端身份调整配置。

## 2. 在 R4 填配置

编辑 `/etc/config/npu_tunnel`；PSK 与 PPP 密码仅留在设备上，不要放进提交或验收日志。
以下地址为文档占位，必须替换：

```sh
chmod 600 /etc/config/npu_tunnel
uci set npu_tunnel.main.peer='203.0.113.10'
uci set npu_tunnel.main.psk='REPLACE_WITH_THE_SAME_64_HEX_CHARACTERS'
uci set npu_tunnel.main.username='r4user'
uci set npu_tunnel.main.password='REPLACE_WITH_PPP_PASSWORD'
uci add_list npu_tunnel.main.destination='198.51.100.20/32'
uci commit npu_tunnel
mtk-npu-tunnel up
```

`source` 默认 `0.0.0.0/0`，所以策略也可以匹配本机代理核心的外连；也可改成指定 LAN 客户端 `/32`。
把需要通过隧道的代理节点 IP 加入 `destination`，可让其外层连接经 L2TP/IPsec 发出。
本机核心新建的 socket 仍从 CPU 发包，其 PPE/NPU 资格需另验收；此路由配置不保证提高代理速度。
核心若强制绑定 WAN 设备，需要调整该绑定。域名需先确定实际节点 IP，并随地址变化更新策略。
对于直接转发的客户端目标，先在 PassWall/OpenClash 中将相同目标设为直连，避免透明代理先截获。
不要同时把同一条连接当作“直连分流”和“代理节点外连”验收。

`up` 先生成配置、检查 fw4，再注册 WAN 的 ESP offload 特性、打开 HNAT 的 `tnl_toggle`、协商硬件 packet SA，最后启动 L2TP。
若安装了 TurboACC，也会保存其原开关值并启用隧道卸载；`remove` 会恢复未被用户另行更改的原值。
如果 SA 协商或硬件 offload 被拒绝，会保持 L2TP 关闭；不会退化成明文 L2TP。
明文保护规则及表 201 的 unreachable 兜底会保留。未选目标及 LAN 管理网段仍使用原路由。
部署前会保存初始 network/firewall 配置到 `/etc/npu-tunnel-backup`；配置生成失败自动还原当次更改。

确认连接、策略与负载均正常后，启用开机连接；WAN 后续获取或更新地址时也会重试：

```sh
uci set npu_tunnel.main.enabled='1'
uci commit npu_tunnel
/etc/init.d/npu-tunnel enable
```

## 3. 验收

```sh
mtk-npu-tunnel status
# 把下面地址替换成一个已配置的目标 IP：
ip -4 route get 198.51.100.20
cat /proc/npu/tnl
```

需要同时核对：

1. SA 显示 INSTALLED，L2TP 接口 up，目标实际路由经 `l2tp-npu_l2tp`、表 201。
2. 目标流量正在运行时，NPU 对应 L2TP 条目 encap/decap 均生效；加密上下文 CDRT 非零。
3. 对应 PPE 元组进入 BIND，硬件计数随真实流量增长；SA 重协商、隧道重连后仍能恢复。
4. 停止隧道时目标不可达；未选目标继续走原 WAN；明文 UDP 1701 规则没有放行未受保护的包。

NPU 参数同步、非零 CDRT、EIP 中断或 CPU 使用率，均不能单独证明双向硬件卸载。
`mtk_crypto/xfrm_params` 的字节/包数来自主机经过驱动的观察，可能不覆盖始终在硬件内的包。
Traffic 的 WAN 速率来自接口；隧道参数、NPU 忙碌率、经验证的 DMA 回送计数分别显示，不相加。
本入口的离线配置检查与编译不能替代上述实机验收。

## 停止与移除

```sh
mtk-npu-tunnel down    # 保留策略和不可达兜底
mtk-npu-tunnel remove  # 停止、移除本工具的配置和开机入口，目标恢复原路由
```

`remove` 仅删除标记为本工具所有的配置项，不回滚部署后其他网络修改。
