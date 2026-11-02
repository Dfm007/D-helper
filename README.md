# D-helper

macOS 上的华硕 ROG 笔电控制面板：切风扇档位、看温度/转速/频率/功耗，并在菜单栏常驻关键读数。

用 SwiftUI + IOKit 写成，不依赖 Xcode 工程，`./build.sh` 直接出 `D-helper.app`（通用二进制）。

---

## 功能

**主界面**

- 四个档位按钮：静音 / 平衡 / 增强 / 自定义（自定义尚未实现，点击无动作）
- 顶部两行状态：`CPU 62°C 风扇 4860 RPM` / `GPU 50°C 风扇 3540 RPM`
- 功耗与频率曲线：双曲线（频率 GHz / 功耗 W），横轴固定 96 秒窗口，标注最高与最低值
- 当前档位**由 EC 回读得出**，不靠本地记忆——重启后界面显示的就是真实生效的档位

**设置页**

- 菜单栏显示项（进入独立面板）
- 开机自启：登录时静默启动，不弹窗口也不闪窗
- 重启后自动恢复曲线：由 root 守护进程开机重写上次下发的曲线
- 采样间隔：1 / 2 / 3 秒，改完立即生效
- 版本号（读自 Info.plist）

**菜单栏**

- 图标 + 数值常驻显示，可选 6 项指标，用箭头调整左右顺序
- 「合并温度与转速」：CPU / GPU 各合成一组，温度在上、转速在下
- 全部取消勾选时显示文字图标 `D-helper`
- 排在菜单栏最左边：登录自启时会等其它登录项起齐再建状态项（约 5 秒）；也可按住 ⌘ 拖动调整，位置会记住
- **左键或右键**点击图标都弹出菜单（打开主界面 / 设置… / 退出）
- 应用是 Accessory（`LSUIElement`）：程序坞不显示图标，只驻留菜单栏

---

## 数据来源

| 指标 | 通道 |
|---|---|
| CPU 温度 | AppleSMC · `TC0P`（sp78 定点，/256） |
| CPU 风扇转速 | AppleSMC · `F0Ac`（fpe2 → RPM） |
| GPU 风扇转速 | AppleSMC · `F1Ac` |
| GPU 温度 | IORegistry `IOAccelerator` → `PerformanceStatistics` → `Temperature(C)` |
| CPU 频率 / 封装功耗 | `AMDRyzenCPUPowerManagement` 用户客户端 selector 4 |
| 当前档位 | AppleSMC · `AFW1..4` 回读后与预设曲线比对 |

写路径（改档位）与读取路径一致：`AFMf` 选风扇 → `AFW1..4` 填 8 点温度/占空 → `AFWg` 触发。

---

## 目录结构

```
Sources/
├── main.swift              入口：参数分流（CLI / 离屏渲染 / GUI）
├── DHelperApp.swift        App 与 AppDelegate
├── MainWindow.swift        主窗口（AppKit 持有，按需创建）
├── ModeBarView.swift       主界面
├── PowerFreqSection.swift  功耗与频率曲线（Canvas 绘制）
├── SettingsPage.swift      设置页
├── MenuBarSettingsView.swift  菜单栏设置（勾选 / 合并 / 排序）
├── Palette.swift           配色
├── GPUCardGlyph.swift      显卡卡片图标（SwiftUI）
│
├── FanStore.swift          采样循环 + 档位下发中枢
├── Sensors.swift           温度 / 转速 / kext 状态
├── AMDProcessor.swift      AMD kext selector 4
├── FanECReadback.swift     回读 EC 曲线判档位
├── FanPresets.swift        曲线模型 + 写 EC
├── FanRestore.swift        开机恢复曲线（root 守护进程）
├── LaunchAtLogin.swift     开机自启（LaunchAgent）
├── Admin.swift             osascript 提权通道
├── CLI.swift               fan / sensors 子命令
│
├── MenuBarMetric.swift     菜单栏可选指标定义
├── MenuBarPrefs.swift      勾选 / 顺序 / 合并（持久化）
├── MenuBarController.swift NSStatusItem + 位图合成
├── ChildPanel.swift        无边框子面板（设置 / 菜单栏共用）
│
├── SMCClient.swift         AppleSMC 读写封装
└── SMCBridge.h / .c        AppleSMC 的 C 桥

Resources/
├── Info.plist
├── AppIcon.icns            应用图标（由 design/make-icon.sh 生成）
└── fan_presets.json        风扇曲线（G713PV）

design/
├── app-icon-D-1024.png     图标源图（1024×1024，带透明）
└── make-icon.sh            生成 Resources/AppIcon.icns
```

---

## 构建

```bash
./build.sh            # 通用二进制（x86_64 + arm64）+ ad-hoc 签名
./build.sh arm64      # 只编指定架构
```

依赖 Xcode Command Line Tools（`clang` + `swiftc`），不需要 Xcode 工程。

产物：`build/D-helper.app`

---

## 命令行

```bash
D=./build/D-helper.app/Contents/MacOS/D-helper

$D fan status          # 转速 + kext 状态
$D fan current         # 回读 EC 实际曲线与档位（免 root）
$D fan list            # 列出可用档位
$D fan set silent      # 下发档位（需 root，同时记录曲线并装守护进程）
$D fan restore         # 重放上次下发的曲线（守护进程调用，需 root）
$D fan autostart on|off|status   # 开机恢复守护进程
$D sensors             # 实时频率 / 功耗 / 温度 / 转速
$D --render out.png [settings] [--dark]   # 离屏渲染界面
```

---

## 文件位置

| 用途 | 路径 |
|---|---|
| 用户偏好 | `~/Library/Preferences/dev.dhelper.app.plist`（`autoRestore` / `samplingRate` / `menuBarMetrics` / `menuBarMerge`） |
| 待恢复曲线 | `/var/db/dhelper/fan-state.json` |
| 开机恢复守护进程 | `/Library/LaunchDaemons/dev.dhelper.fanrestore.plist` |
| 守护进程日志 | `/var/log/dhelper-fanrestore.log` |
| 开机自启 | `~/Library/LaunchAgents/dev.dhelper.autostart.plist` |

---

## 设计说明

**为什么写 EC 需要 root**：`AFW1..4` 是 SMC 的可写键，只有 root 能写。程序用 `osascript` 的 `do shell script ... with administrator privileges` 以管理员身份重跑自身的 CLI，只在执行那一下弹一次授权框，进程本身不常驻 root。

**为什么开机要重写曲线**：曲线写在 EC 寄存器里，掉电即丢。`AFWBackC/G` 只是开机扫描的预设槽位快照，救不回来。所以由 root 守护进程在开机时读 `fan-state.json` 重放一次。

**为什么菜单栏用位图**：SwiftUI 的 `MenuBarExtra` label 只认单个 `Text` 或 `Image`，图标 + 文字混排只会显示第一个。这里把整段内容画进一张**模板图**（`isTemplate = true`），交给 `NSStatusItem`，并由系统按菜单栏外观染色。

**为什么主窗口不用 `WindowGroup`**：`WindowGroup` 在应用启动那一刻就把窗口建好并 `orderFront`，拦不住。开机自启要「不弹窗口」只能事后 `orderOut`，中间已经渲染过一帧，于是每次登录都看到主界面一闪而过。现在窗口由 `MainWindow` 自己持有，只从菜单栏「打开主界面」时才创建，启动路径里根本没有建窗这一步。采样循环也因此挪到 `AppDelegate` 里启动，不再依赖 `ModeBarView.onAppear`。

**为什么开机后菜单栏项晚几秒才出现**：状态项的位置只由创建顺序决定——新建的插在最左边，后来者把先来的往右挤。开机时我们起得早，ChatGPT / BetterDisplay 这些登录项随后陆续起来，会一路把我们挤到右边。所以在自启路径上延后 5 秒再建，落在最左边。手动启动没有这个顾虑，立刻建。另外状态项带 `autosaveName`，按住 ⌘ 拖动调整的位置会被系统记住。

**为什么设置页不是 sheet**：sheet 是窗口模态，弹出时 AppKit 会禁用父窗口的红绿灯。改用挂在主窗口下的无边框子窗口，贴在标题栏正下方，外观接近 sheet，但不阻塞主窗口。

---

## 已知限制

- 风扇曲线固定为 `fan_presets.json`（G713PV / 魔霸7 Plus），没有做机型识别
- 「自定义」档位尚未实现
- 菜单栏暂不支持 CPU/GPU 占用率、内存、网速（`MenuBarMetric` 加 case 即可扩展）
- 需要 `SMCAsusFan.kext` 已加载，否则写曲线与档位回读均不可用
- ad-hoc 签名，不能用 `SMAppService` 注册开机自启，故走 LaunchAgent
