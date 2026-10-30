//
//  FanECReadback.swift
//  从 SMCAsusFan.kext 回读 EC 里的当前风扇曲线，判断实际生效档位
//
//  kext 把当前 EC 曲线参数放在 SMC 键 AFW1..4：
//    AFW1/2 = 温度点，AFW3/4 = 占空比。
//    每个 ui32 按「小端打包、SMC 大端存储」，还原时每个键的 4 个字节都要倒序。
//
//  注意：AFWBackC/G 是开机扫描的预设槽位快照，不会随下发变化，
//  不能用来判断「刚下发的档位」。真正反映当前生效曲线的是 AFW1..4。
//

import Foundation

/// 一条 8 点曲线（EC 回读值）
struct ECCurve: Equatable {
    var temp: [Int]
    var duty: [Int]

    /// 与预设比对。EC 写入可能有量化误差，温度和占空都给小容差。
    func matches(_ curve: FanCurve, tempTolerance: Int = 1, dutyTolerance: Int = 2) -> Bool {
        guard temp.count == curve.temp.count, duty.count == curve.duty.count else { return false }
        for i in 0..<temp.count where abs(temp[i] - curve.temp[i]) > tempTolerance { return false }
        for i in 0..<duty.count where abs(duty[i] - curve.duty[i]) > dutyTolerance { return false }
        return true
    }
}

enum FanECReadback {

    /// 当前实际曲线：从 SMC 参数键 AFW1..4 解出
    static func activeCurve() -> ECCurve? {
        let smc = SMCClient.shared
        guard let w1 = try? smc.read("AFW1"), let w2 = try? smc.read("AFW2"),
              let w3 = try? smc.read("AFW3"), let w4 = try? smc.read("AFW4"),
              w1.count == 4, w2.count == 4, w3.count == 4, w4.count == 4 else {
            return nil
        }
        let temps = Array(w1.reversed()) + Array(w2.reversed())
        let duties = Array(w3.reversed()) + Array(w4.reversed())
        return ECCurve(temp: temps.map(Int.init), duty: duties.map(Int.init))
    }

    /// 用单条当前曲线与三档预设比对（CPU/GPU 任一命中即返回档位）
    static func matchPreset(curve: ECCurve?, presets: FanPresets?,
                            order: [String] = ["silent", "balanced", "performance"]) -> String? {
        guard let curve, let presets else { return nil }
        for name in order {
            guard let preset = presets.preset(name) else { continue }
            if curve.matches(preset.cpu) || curve.matches(preset.gpu) {
                return name
            }
        }
        return nil
    }
}
