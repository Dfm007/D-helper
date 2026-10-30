//
//  FanStore.swift
//  采样 + 档位下发的中枢
//
//  采样走一条串行队列（SMCClient 只持有一个 AppleSMC 连接，不并发调），
//  回主线程只写几个 @Published。
//

import SwiftUI
import Combine

final class FanStore: ObservableObject {
    static let shared = FanStore()

    // 实时读数
    @Published private(set) var cpuTemp: Double?
    @Published private(set) var gpuTemp: Double?
    @Published private(set) var cpuRPM = 0
    @Published private(set) var gpuRPM = 0
    @Published private(set) var kextLoaded = false

    // 频率与功耗（AMDRyzenCPUPowerManagement selector 4）
    @Published private(set) var powerWatts: Double?
    @Published private(set) var freqGHz: Double?
    /// 曲线历史：2 秒一个点，48 点 = 96 秒窗口
    @Published private(set) var freqHistory: [Double] = []
    @Published private(set) var powerHistory: [Double] = []

    /// 正在下发的档位（nil = 空闲）
    @Published private(set) var applying: String?
    /// 下发失败的说明
    @Published private(set) var message: String?
    /// 当前档位：由 EC 回读 AFW1..4 后与三档比对得出。
    /// nil 表示三档都不匹配（出厂曲线 / 别人写的自定义曲线）。
    @Published private(set) var current: String?

    /// 重启后自动恢复（用户意图，默认开）。
    /// 真正的守护进程在下发档位时按这个意图安装/卸载。
    @Published private(set) var autoRestoreEnabled: Bool
    /// 守护进程当前是否真的装在系统里（只读展示）
    @Published private(set) var autoRestoreInstalled = FanAutoRestore.isInstalled
    /// 正在装/卸守护进程
    @Published private(set) var autoRestoreBusy = false
    private static let autoRestoreKey = "autoRestore"

    /// 采样间隔（秒）：1 / 2 / 3，改了就真的按新节奏采
    @Published private(set) var samplingRate: Int
    private static let samplingKey = "samplingRate"
    /// 曲线窗口固定 96 秒，所以点数随间隔变化
    var historyLimit: Int { max(12, 96 / max(1, samplingRate)) }

    private let queue = DispatchQueue(label: "dev.dhelper.sample")
    private var timer: Timer?
    private var presets: FanPresets?    /// 正在等待 EC 确认的档位。
    /// 从点下按钮那一刻起就要冻结「回读覆盖」——否则授权框还开着的时候，
    /// 采样读到的仍是旧曲线，会把选中态打回原档，看起来像"没切换"。
    private var expectedPreset: String?
    private var expectationDeadline = Date.distantPast

    private init() {
        // 早期版本在这里记过「上一次档位」，现在真值只认 EC 回读，清掉这个残留键
        UserDefaults.standard.removeObject(forKey: "fan.preset")

        // 没写过时视为开启：object(forKey:) 为 nil 也要当成 true
        autoRestoreEnabled = UserDefaults.standard.object(forKey: Self.autoRestoreKey) as? Bool ?? true
        let savedRate = UserDefaults.standard.object(forKey: Self.samplingKey) as? Int ?? 2
        samplingRate = min(3, max(1, savedRate))
        // 不做本地记忆：真实档位只认 EC 回读，首轮采样后就会有值
        presets = try? FanPresets.load()
    }

    // MARK: 采样

    func start() {
        refresh()
        restartTimer()
    }

    /// 按当前采样间隔装定时器
    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(samplingRate), repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// 改采样间隔：立刻生效并落盘。
    /// 时间轴变了，旧的历史点混着新节奏画会误导，所以清空重来。
    func setSamplingRate(_ seconds: Int) {
        let value = min(3, max(1, seconds))
        guard value != samplingRate else { return }
        samplingRate = value
        UserDefaults.standard.set(value, forKey: Self.samplingKey)
        freqHistory.removeAll()
        powerHistory.removeAll()
        restartTimer()
        refresh()
    }

    func refresh() {
        queue.async {
            let amd = AMDProcessorClient.shared.sample()
            // TC0P 读不到时退回 kext 给的封装温度
            let cpuT = Sensors.cpuTemp() ?? amd?.packageTemperatureC
            let gpuT = Sensors.gpuTemp()
            let r = Sensors.rpms()
            let kext = Sensors.kextLoaded
            // 实际档位只看 EC 里当前生效的曲线，不看本地记录
            let curve = kext ? FanECReadback.activeCurve() : nil
            let active = FanECReadback.matchPreset(curve: curve, presets: self.presets)
            let power = amd?.powerWatts
            let freq = amd?.averageFrequencyMHz.map { $0 / 1000 }
            DispatchQueue.main.async {
                self.cpuTemp = cpuT
                self.gpuTemp = gpuT
                self.cpuRPM = r.cpu
                self.gpuRPM = r.gpu
                self.kextLoaded = kext

                if let expected = self.expectedPreset {
                    if active == expected {
                        // EC 已经认了，交还给回读值
                        self.current = expected
                        self.expectedPreset = nil
                    } else if Date() >= self.expectationDeadline {
                        // 等太久还没确认：以 EC 为准，并把差异说出来
                        self.current = active
                        self.expectedPreset = nil
                        let label = self.presets?.preset(active ?? "")?.label ?? (active ?? "未知")
                        self.message = "已下发，但 EC 回读仍是「\(label)」，可能未生效"
                    }
                } else {
                    self.current = active
                }

                self.powerWatts = power
                self.freqGHz = freq
                if let f = freq {
                    self.freqHistory.append(f)
                    if self.freqHistory.count > self.historyLimit {
                        self.freqHistory.removeFirst(self.freqHistory.count - self.historyLimit)
                    }
                }
                if let p = power {
                    self.powerHistory.append(p)
                    if self.powerHistory.count > self.historyLimit {
                        self.powerHistory.removeFirst(self.powerHistory.count - self.historyLimit)
                    }
                }
            }
        }
    }

    // MARK: 下发

    /// 切档位：以 root 重跑自身 CLI 写 EC 曲线。
    /// 点下的瞬间就乐观切换选中态并**冻结回读覆盖**（授权框可能开着好几秒，
    /// 期间采样读到的还是旧曲线），成功后主动轮询，等 EC 认了再交还给回读值。
    func apply(_ name: String) {
        guard applying == nil else { return }
        guard current != name else { return }

        let previous = current
        current = name
        applying = name
        message = nil
        expectedPreset = name
        expectationDeadline = Date().addingTimeInterval(8)

        DispatchQueue.global(qos: .userInitiated).async {
            // 关掉自动恢复时带 --no-autostart，让 root 子进程别装守护进程
            // （root 读不到用户偏好域，所以意图必须由参数带过去）
            var args = ["fan", "set", name]
            if !self.autoRestoreEnabled { args.append("--no-autostart") }
            let result = Admin.runSelfAsAdmin(args)
            DispatchQueue.main.async {
                self.applying = nil
                self.autoRestoreInstalled = FanAutoRestore.isInstalled
                if result.ok {
                    // 下发成功但守护进程没装上时，CLI 会带 ⚠️ 前缀，别吞掉
                    if result.output.contains("⚠️") {
                        self.message = result.output
                    }
                    self.scheduleConfirmation()
                } else {
                    self.expectedPreset = nil
                    self.current = previous
                    self.message = Admin.friendlyError(result.output)
                }
                // 无论成败都立刻回读一次，让界面以 EC 为准
                self.refresh()
            }
        }
    }

    /// 下发成功后主动拉几次读数：EC 生效通常在 1 秒内，
    /// 只靠 2 秒定时器会显得慢半拍，用户会以为没切过去。
    private func scheduleConfirmation() {
        for delay in [0.6, 1.4, 2.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.expectedPreset != nil else { return }
                self.refresh()
            }
        }
    }

    // MARK: 开机自动恢复

    /// 设置里切换：先乐观翻转，**只有 root 操作真的成功才落盘偏好**。
    /// 用户在授权框点取消 → osascript 返回失败 → 这里回滚，界面不会显示"已关闭"。
    func setAutoRestore(_ on: Bool) {
        guard !autoRestoreBusy else { return }
        let previous = autoRestoreEnabled

        autoRestoreEnabled = on          // 乐观：让开关立刻跟手
        message = nil
        autoRestoreBusy = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Admin.runSelfAsAdmin(["fan", "autostart", on ? "on" : "off"])
            DispatchQueue.main.async {
                self.autoRestoreBusy = false
                self.autoRestoreInstalled = FanAutoRestore.isInstalled

                if result.ok {
                    UserDefaults.standard.set(on, forKey: Self.autoRestoreKey)
                    self.autoRestoreEnabled = on
                } else {
                    // 取消 / 失败：意图不变，开关回到原样
                    self.autoRestoreEnabled = previous
                    self.message = Admin.friendlyError(result.output)
                }
            }
        }
    }
}
