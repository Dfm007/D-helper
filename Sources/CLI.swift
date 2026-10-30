//
//  CLI.swift
//  命令行模式：GUI 提权后会以 root 重跑 `D-helper fan set <档位>`
//
//  只保留这一条链路需要的东西：status / list / set。
//

import Foundation

enum CLI {
    static var lastMessage = ""

    private static func emit(_ text: String) {
        lastMessage = text
        print(text)
    }

    static func run(_ args: [String]) -> Int32 {
        guard let cmd = args.first else {
            emit(helpText)
            return 0
        }
        let rest = Array(args.dropFirst())
        switch cmd {
        case "fan", "fans":
            return fanCommand(rest)
        case "sensors", "sensor":
            return sensorsCommand()
        default:
            emit("ERR 未知命令：\(cmd)\n\(helpText)")
            return 2
        }
    }

    // MARK: 传感器

    /// 打一次实时读数，用来核对 AMD kext 的 selector 4 是否解析正确
    private static func sensorsCommand() -> Int32 {
        guard let m = AMDProcessorClient.shared.sample() else {
            emit("ERR 读不到 AMDRyzenCPUPowerManagement（kext 未加载或 selector 4 不兼容）")
            return 1
        }
        func ghz(_ mhz: Double?) -> String {
            guard let mhz else { return "—" }
            return String(format: "%.2f GHz", mhz / 1000)
        }
        var lines = [
            "核心数      \(m.coreCount)",
            "平均频率    \(ghz(m.averageFrequencyMHz))",
            "最高频率    \(ghz(m.maxFrequencyMHz))",
            "最低频率    \(ghz(m.minFrequencyMHz))",
            "封装功耗    " + (m.powerWatts.map { String(format: "%.1f W", $0) } ?? "—"),
            "封装温度    " + (m.packageTemperatureC.map { String(format: "%.1f °C", $0) } ?? "—")
        ]
        let r = Sensors.rpms()
        lines.append("CPU 转速    \(r.cpu) RPM")
        lines.append("GPU 转速    \(r.gpu) RPM")
        emit(lines.joined(separator: "\n"))
        return 0
    }

    // MARK: 风扇

    private static func fanCommand(_ args: [String]) -> Int32 {
        let sub = args.first ?? "status"
        switch sub {

        case "status":
            let ctrl = FanController()
            let r = ctrl.rpms()
            var lines = [
                "kext      " + (ctrl.isKextLoaded ? (ctrl.kextBuild ?? "已加载") : "未加载（AFMd 不存在）"),
                "CPU 转速  \(r.cpu) RPM",
                "GPU 转速  \(r.gpu) RPM"
            ]
            if !FanController.isPrivileged { lines.append("（下发曲线需要 root）") }
            emit(lines.joined(separator: "\n"))
            return ctrl.isKextLoaded ? 0 : 1

        case "current":
            // 回读 EC 里真实生效的曲线，判断实际档位（免 root）
            guard let curve = FanECReadback.activeCurve() else {
                emit("ERR 读不到 EC 当前曲线（AFW1..4），SMCAsusFan 未加载或版本不支持")
                return 1
            }
            var lines = [
                "温度      \(curve.temp)",
                "占空      \(curve.duty)"
            ]
            let presets = loadPresets()
            if let name = FanECReadback.matchPreset(curve: curve, presets: presets) {
                lines.append("实际档位  \(presets?.preset(name)?.label ?? name)（\(name)）")
            } else {
                lines.append("实际档位  与三档预设都不一致（出厂曲线或自定义）")
            }
            emit(lines.joined(separator: "\n"))
            return 0

        case "list":
            guard let presets = loadPresets() else { return 1 }
            let lines = presets.names.compactMap { name -> String? in
                guard let p = presets.preset(name) else { return nil }
                return "\(name)\t\(p.label ?? "")"
            }
            emit(lines.isEmpty ? "配置里没有可用档位" : lines.joined(separator: "\n"))
            return lines.isEmpty ? 1 : 0

        case "set":
            guard args.count >= 2 else {
                emit("ERR 用法：fan set <silent|balanced|performance> [--no-autostart]")
                return 2
            }
            let name = args[1]
            // 用户在设置里关掉了「重启后自动恢复」时，GUI 会带这个参数
            let skipAutostart = args.contains("--no-autostart")
            guard FanController.isPrivileged else {
                emit("ERR 需要 root 权限才能写 SMC 键")
                return 3
            }
            guard let presets = loadPresets(), let preset = presets.preset(name) else {
                emit("ERR 找不到档位：\(name)")
                return 2
            }
            let ctrl = FanController()
            guard ctrl.isKextLoaded else {
                emit("ERR SMCAsusFan.kext 未加载（AFMd 不存在），无法写曲线")
                return 1
            }
            do {
                try ctrl.apply(preset.cpu, fan: .cpu)
                // kext 处理 AFWg 是异步的：两只风扇连着写要留间隙，
                // 否则第二次改写 AFMf 会让第一次触发读到新的风扇号
                Thread.sleep(forTimeInterval: 0.25)
                try ctrl.apply(preset.gpu, fan: .gpu)

                // 记下实际下发的曲线，供开机守护进程重放（EC 掉电会丢曲线）
                _ = FanStateStore.save(FanApplyState(mode: "preset",
                                                     label: preset.label ?? name,
                                                     cpu: preset.cpu,
                                                     gpu: preset.gpu,
                                                     time: Date()))

                // 默认开启「重启后自动恢复」：顺手确保守护进程在位。
                // 此刻已经是 root（就是这次提权），不需要再弹一次授权框。
                // 若用户已在设置里关掉（--no-autostart），则不但不装，还清掉已有的。
                var extra = ""
                if skipAutostart {
                    if FanAutoRestore.isInstalled {
                        FanAutoRestore.uninstall()
                        extra = "\n已按设置关闭开机自动恢复"
                    }
                } else if let exe = Bundle.main.executablePath,
                          !FanAutoRestore.isInstalled || FanAutoRestore.installedExecutable != exe {
                    do {
                        try FanAutoRestore.install(executable: exe)
                        extra = "\n已开启开机自动恢复（\(FanAutoRestore.label)）"
                    } catch {
                        extra = "\n⚠️ 开机自动恢复安装失败：\(error.localizedDescription)"
                    }
                }

                emit("OK 已切到 \(name)（\(preset.label ?? "")）\(extra)")
                return 0
            } catch {
                emit("ERR 下发失败：\(error.localizedDescription)")
                return 4
            }

        case "restore":
            // 开机由 root 守护进程调用：把上次下发的曲线重新写回 EC
            guard FanController.isPrivileged else {
                emit("ERR 需要 root 权限（该子命令由守护进程 \(FanAutoRestore.label) 调用）")
                return 3
            }
            let r = FanAutoRestore.restoreNow()
            emit((r.ok ? "OK " : "ERR ") + r.message)
            return r.ok ? 0 : 4

        case "autostart", "auto":
            let action = args.count >= 2 ? args[1] : "status"
            switch action {
            case "status":
                var lines = [
                    "守护进程    \(FanAutoRestore.isInstalled ? "已安装" : "未安装")",
                    "label      \(FanAutoRestore.label)",
                    "plist      \(FanAutoRestore.plistPath)"
                ]
                if let exe = FanAutoRestore.installedExecutable {
                    lines.append("指向        \(exe)")
                }
                if FanAutoRestore.isInstalled,
                   let exe = FanAutoRestore.installedExecutable,
                   let current = Bundle.main.executablePath, exe != current {
                    lines.append("⚠️ App 位置已变，需重新下发一次或 autostart on 修复")
                }
                if let s = FanStateStore.load() {
                    let when = s.time.formatted(date: .abbreviated, time: .shortened)
                    lines.append("待恢复      \(s.label)（\(when) 下发）")
                } else {
                    lines.append("待恢复      无记录")
                }
                emit(lines.joined(separator: "\n"))
                return 0
            case "on", "install", "enable":
                guard FanController.isPrivileged else {
                    emit("ERR 需要 root 权限才能安装开机守护进程")
                    return 3
                }
                guard let exe = Bundle.main.executablePath else {
                    emit("ERR 找不到当前可执行文件路径")
                    return 4
                }
                do {
                    try FanAutoRestore.install(executable: exe)
                    emit("OK 已开启：开机以 root 重放上次下发的曲线\n指向 \(exe)")
                    return 0
                } catch {
                    emit("ERR 安装失败：\(error.localizedDescription)")
                    return 4
                }
            case "off", "uninstall", "disable":
                guard FanController.isPrivileged else {
                    emit("ERR 需要 root 权限才能卸载开机守护进程")
                    return 3
                }
                FanAutoRestore.uninstall()
                emit("OK 已关闭：重启后不再自动恢复风扇曲线")
                return 0
            default:
                emit("ERR 用法：fan autostart on | off | status")
                return 2
            }

        default:
            emit("ERR 未知子命令：\(sub)\n用法：fan status | fan current | fan list | fan set <档位> | fan restore | fan autostart on|off|status")
            return 2
        }
    }

    private static func loadPresets() -> FanPresets? {
        do {
            return try FanPresets.load()
        } catch {
            emit("ERR 读不到风扇曲线配置：\(error.localizedDescription)")
            return nil
        }
    }

    private static let helpText = """
    用法：D-helper <命令>

      fan status          风扇转速 + kext 状态
      fan current         回读 EC 实际生效曲线与档位（免 root）
      fan list            列出可用档位
      fan set <档位>       下发档位曲线（需 root，同时开启开机自动恢复）
      fan restore         把上次下发的曲线重写回 EC（守护进程调用，需 root）
      fan autostart on|off|status   开机自动恢复守护进程（需 root）
      sensors             实时频率/功耗/温度/转速
    """
}
