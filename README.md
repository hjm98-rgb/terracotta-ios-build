# 陶瓦 iOS 独立客户端（Terracotta for iOS）

把 PC/安卓上的陶瓦联机（Terracotta）搬到 iPhone / iPad 上，做成一个**独立 App**：
不依赖紫水晶改版、不绑启动器，任何 iOS 上的 Java 版启动器（紫水晶 / PojavLauncher / FCL-iOS）都能用它联机。

---

## 0. 先核对事实（这些决定了架构，不能拍脑袋）

| 项目 | 结论 |
|---|---|
| EasyTier 官方 iOS 支持 | **有**。仓库里 `easytier-contrib/easytier-ios`，带 `build-xcframework.sh`，产出 `libeasytier_ios.a` |
| iOS 绑定是否走 TUN / NEPacketTunnel | **不走**。头文件明写：*"embeds EasyTier into an iOS app without a TUN device or NEPacketTunnel"*，靠 **loopback 端口转发 + 管理 RPC** |
| 端口转发怎么配 | `easytier_ios_call_json_rpc("api.config.ConfigRpcService", "PatchConfig", ...)`，或直接把 `[[port_forward]]` 写进 TOML |
| 陶瓦邀请码格式 | `U/XXXX-XXXX-XXXX-XXXX`，34 进制（`0-9A-HJ-NP-Z`），值必须是 **7 的倍数** |
| 邀请码 → 网络参数 | 前 8 位 = `network_name = scaffolding-mc-XXXX-XXXX`，后 8 位 = `network_secret = XXXX-XXXX` |
| 房主虚拟 IP | **固定 `10.144.144.1`** |
| 房主端口怎么告诉别人 | 房主 hostname 固定为 `scaffolding-mc-server-<MC端口>`，房客解析 hostname 拿端口 |
| 公共中转节点 | `tcp://public.easytier.top:11010`、`tcp://public2.easytier.cn:54321`，以及 zkitefly 的两个 https 节点 |
| 双方启动参数 | 都是 `--no-tun` + `--latency-first` + `--multi-thread` + `--enable-kcp-proxy` + `--p2p-only`，房主额外 `ipv4=10.144.144.1` + tcp/udp 白名单 |

所以：**iOS 端做房主、做房客，全都不需要 TUN**，只要 loopback 监听 + 端口转发，这正是 easytier-ios 的原生能力。

---

## 1. 架构

```
┌───────────────────────────── iPhone ─────────────────────────────┐
│                                                                  │
│  ┌──────────────┐   providerMessage    ┌───────────────────────┐  │
│  │ 主 App        │◄────────────────────►│ Network Extension     │  │
│  │ (SwiftUI)     │  start/stop/status   │ (PacketTunnelProvider)│  │
│  │  UI + 邀请码   │  /log（JSON）        │  ┌─────────────────┐  │  │
│  └──────────────┘                       │  │ EasyTier 实例    │  │  │
│                                          │  │ libeasytier_ios │  │  │
│        紫水晶 / 启动器                     │  └─────────────────┘  │  │
│        └── 多人游戏 → 127.0.0.1:25565 ────► loopback 端口转发      │  │
│                                          └───────────┬───────────┘  │
└──────────────────────────────────────────────────────┼───────────┘
                                                       │ UDP/TCP 打洞
                            公共节点 (public.easytier.top) + P2P
                                                       │
                                       房主设备 / HFML、PCL、FCL
```

要点：
1. **EasyTier 跑在 Network Extension 进程里**，不是主 App。App 被切后台/被杀都不影响组网（这就是后台保活的核心，见第 3 节）。
2. 主 App 只负责 UI 和发指令，通过 `NETunnelProviderSession.sendProviderMessage` 双向通信，**不用 App Group**（App Group 需要额外的 App ID 能力，个人证书容易签不过，这里刻意绕开）。
3. 紫水晶永远连 `127.0.0.1:<端口>` —— 因为转发监听在 NE 进程里，loopback 是全设备共享的。

---

## 2. 两种角色怎么跑

### 房主（iOS 开房）
1. 用户在 MC 里「对局域网开放」，记下端口 P。
2. App 生成房间码（或手填），构造 TOML：
   ```toml
   instance_name = "terracotta-ios-host"
   hostname = "scaffolding-mc-server-<P>"
   ipv4 = "10.144.144.1"
   listeners = ["tcp://0.0.0.0:0", "udp://0.0.0.0:0"]
   rpc_portal = "127.0.0.1:0"

   [network_identity]
   network_name = "scaffolding-mc-XXXX-XXXX"
   network_secret = "XXXX-XXXX"

   [flags]
   no_tun = true
   latency_first = true
   enable_kcp_proxy = true
   multi_thread = true
   p2p_only = true
   relay_network_whitelist = "<P>"

   [[peer]]
   uri = "tcp://public.easytier.top:11010"
   ```
3. 结果：别人连 `10.144.144.1:P`，流量落到房主本机 `127.0.0.1:P`（EasyTier 白名单机制）。

### 房客（iOS 加房）
1. 粘贴邀请码 → 解出 network_name / secret。
2. `dhcp = true` 起实例，`hostname = terracotta-ios-guest`。
3. 轮询 peer 列表，找 hostname 以 `scaffolding-mc-server-` 开头的节点，解析出房主端口 P。
4. 加一条转发 `bind 0.0.0.0:P → dst 10.144.144.1:P`（TCP+UDP）。
   - 主路径：`PatchConfig` RPC 动态加；
   - 兜底路径：停实例 → 带上 `[[port_forward]]` 重新起（代码里两条都写了，RPC 失败自动降级）。
5. App 显示「在游戏里连接 127.0.0.1:P」。

> 注：陶瓦的 scaffolding TCP 协议（`c:ping` / `c:server_port` / `c:player_ping`，带 16 字节指纹校验）只用于「房间大厅 / 好友列表」。iOS 端这里走精简版：**靠 hostname 拿端口**，省掉整层协议，联机本身完全一致，和 PC 端互通不受影响。

---

## 3. 后台怎么保持运行（重点）

iOS 的后台规则很硬：普通 App 进后台约 30 秒到几分钟就被挂起，进程冻住，Rust 的 tokio 线程全停。所以**不能把 EasyTier 放主 App**。

### 方案 A（采用）：Network Extension 当"常驻容器"
- `NEPacketTunnelProvider` 一旦 `status == .connected`，**系统会持续为它保留进程**，App 被挂起、被划掉都不影响它。
- 我们不需要真的接管流量，只 `setTunnelNetworkSettings` 一个最小配置（MTU + 一个私有网段、不加路由），真正的数据面走 EasyTier 的 loopback 监听。
- 这样做的代价：系统顶部会出现 VPN 图标，且同一时间只能有一个 NE 处于 connected。
- 好处：**用户切到紫水晶玩游戏时，陶瓦在后台照常转发**，不会断。

配套加固：
- `onDemandRules = [NEOnDemandRuleConnect()]` + `isOnDemandEnabled = true`：断网、切 WiFi/蜂窝、重启后系统会自动把隧道拉起来。
- `provider` 里起 `DispatchSourceTimer` 做 5 秒心跳，检测实例存活、peer 变化，顺带防止系统判定空闲回收。
- `sleep`/`wake` 处理：`NEPacketTunnelProvider` 收到 `sleep` 回调时只暂停轮询，不清实例。

### 方案 B（备选，iOS 26+）：`BGContinuedProcessingTask`
iOS 26 新增的用户发起型后台继续任务，进度可见、可延长。适合"不想开 VPN 图标"的用户，但**时长有上限**，长局游戏会断。代码里留了开关位。

### 方案 C（不推荐）：后台音频
伪造静音音频循环保活。自签能用，但耗电、且行为不干净，不写进默认路径。

### 还需要用户手动保证的
- 设置 → 隐私与安全 → 本地网络：允许「陶瓦」
- 低电量模式下 NE 更容易被系统回收，提示用户关掉
- 别同时开别的代理类 App（同一个 NE 槽位会打架）

---

## 4. UI 设计（就按这个做）

风格：MC 味深色 + 陶土橙，全等宽字体，2px 描边硬卡片，无圆角滥用。

| 页面 | 内容 |
|---|---|
| **首页** | 顶部状态条（未连接 / 组网中 / 已连接 · 延迟）；两张大卡：`我是房主`（开房）、`我是房客`（加入）；底部最近房间 + 日志入口 |
| **房主页** | MC 局域网端口输入（带"自动扫描本机端口"按钮）；房间码生成卡（大字展示 `U/XXXX-...`，一键复制、二维码）；成员列表（头像色块 + 昵称 + 延迟） |
| **房客页** | 邀请码输入（自动补 `U/`、自动分 4 位一组、粘贴识别）；扫码入口；连接进度 5 步（起实例 → 打洞 → 找房主 → 加转发 → 就绪） |
| **房间页** | 连接地址大卡 `127.0.0.1:25565`（一键复制）；NAT 类型与连接难度（绿/黄/红）；成员；断开按钮 |
| **日志页** | 实时滚动，分级着色，可导出 |

配色（`Theme.swift` 里已封装）：
- 背景 `#14110F`，卡片 `#1E1916`，描边 `#3A2F28`
- 主色陶土橙 `#D97A45`，成功 `#6FA96A`，警告 `#D9B245`，错误 `#C7564C`
- 文本 `#EDE6DF` / 次文本 `#9C8E82`

---

## 5. 目录

```
terracotta-ios/
├── project.yml                     # XcodeGen 工程定义
├── App/                            # 主 App（SwiftUI）
│   ├── TerracottaApp.swift
│   ├── AppModel.swift              # 全局状态 + NE 指令
│   ├── Theme.swift
│   ├── RootView.swift              # 首页 + 路由
│   ├── HostView.swift
│   ├── JoinView.swift
│   ├── RoomView.swift
│   ├── LogView.swift
│   ├── Info.plist
│   └── Terracotta.entitlements
├── Tunnel/                         # Network Extension
│   ├── PacketTunnelProvider.swift  # 常驻容器 + 指令处理
│   ├── TunnelEngine.swift          # EasyTier 实例编排 / peer 发现 / 转发
│   └── TerracottaTunnel.entitlements
├── Shared/                         # 两端共用
│   ├── InviteCode.swift            # 陶瓦 34 进制编解码（与 PC 端逐字节对齐）
│   ├── EasyTierConfig.swift        # TOML 构造
│   ├── TunnelContract.swift        # 主 App ↔ NE 指令协议
│   └── EasyTierIOS.swift           # C FFI 封装
├── Bridge/
│   ├── easytier-ios.h
│   └── Terracotta-Bridging-Header.h
├── Frameworks/                     # CI 编译产出 libeasytier_ios.a 放这里
├── scripts/ci-build-rust.sh
└── .github/workflows/build-ipa.yml
```

---

## 6. 构建 / 打包（GitHub Actions + 个人证书自签）

1. push 到 GitHub，`.github/workflows/build-ipa.yml` 自动：
   - `macos-14` runner 上 clone EasyTier，`rustup target add aarch64-apple-ios`
   - 编译 `libeasytier_ios.a`（device slice）
   - `xcodegen` 生成工程 → `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO`
   - 打 `Payload/Terracotta.app` → zip → `Terracotta-unsigned.ipa` 工件
2. 下载未签名 IPA，用你的个人证书 + 描述文件签名（**注意要把内嵌的 `.appex` 一起签**，全能签/小白签默认会递归签名，别只签外层）。
3. 描述文件里必须同时包含：
   - `com.apple.developer.networking.networkextension` = `packet-tunnel-provider`
   - `com.apple.developer.networking.vpn.api`（Allow Personal VPN）
   两个 target（主 App + Tunnel 扩展）的 App ID 都要开这个能力。

---

## 7. 已知限制（先说清楚，省得后面踩）

1. **iOS 只能有一个 NE 在跑**：用户同时开别的加速器会顶掉陶瓦。
2. 静态库塞进 NE 进程，NE 内存上限约 50MB；EasyTier + tokio 正常在 10–20MB，但如果开 debug 日志/多实例要注意。
3. 公共节点是境外节点，国内直连可能慢，App 里给了「自定义节点」输入位。
4. `PatchConfig` 的 protobuf JSON 字段名建议对着 `easytier-proto` 再核一遍；代码里已备好"重启实例带 `[[port_forward]]`"的降级路径，字段错了也不影响可用。
5. 完全没碰 TUN，所以**没有广播包桥接**：MC 局域网列表里不会自动刷出房间，必须走「直接连接」。这是取舍，换来的是不需要真正实现用户态 TCP/IP 栈。
