//
//  MenuBarMetric.swift
//  菜单栏可显示的指标：目前只有 D-helper 已经采到的 6 项
//
//  缺失的（CPU/GPU 占用率、内存、网速）先留空，等框架稳定再补
//  —— 补的时候只需要在这个 enum 里加 case 并实现 value(_:)。
//

import AppKit

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpuTemp
    case cpuFan
    case cpuFreq
    case cpuPower
    case gpuTemp
    case gpuFan

    var id: String { rawValue }

    /// 设置页选项列表的固定顺序（不随菜单栏排序变化）
    static let fixedOrder: [MenuBarMetric] = [
        .cpuTemp, .cpuFan, .cpuFreq, .gpuTemp, .gpuFan, .cpuPower
    ]

    var title: String {
        switch self {
        case .cpuTemp:  return "CPU 温度"
        case .cpuFan:   return "CPU 风扇转速"
        case .cpuFreq:  return "CPU 频率"
        case .cpuPower: return "实时功耗"
        case .gpuTemp:  return "GPU 温度"
        case .gpuFan:   return "GPU 风扇转速"
        }
    }

    /// 列表里那行灰色小字，说明数据从哪来
    var source: String {
        switch self {
        case .cpuTemp:  return "AppleSMC · TC0P"
        case .cpuFan:   return "AppleSMC · F0Ac"
        case .cpuFreq:  return "AMDRyzenCPUPowerManagement · selector 4"
        case .cpuPower: return "AMDRyzenCPUPowerManagement · selector 4"
        case .gpuTemp:  return "IOAccelerator · Temperature(C)"
        case .gpuFan:   return "AppleSMC · F1Ac"
        }
    }

    /// 菜单栏图标（描线风格，便于单色渲染）
    /// （GPU 在菜单栏里不走这里，用自绘的显卡卡片图标）
    var icon: String {
        switch self {
        case .cpuTemp:  return "thermometer.medium"
        case .cpuFan:   return "fanblades.fill"
        case .cpuFreq:  return "speedometer"
        case .cpuPower: return "bolt.fill"
        case .gpuTemp:  return "display"
        case .gpuFan:   return "fanblades"
        }
    }

    /// 图标颜色（菜单栏里用同一套，和界面上一致）
    var tint: NSColor {
        switch self {
        case .cpuTemp:  return NSColor(srgbRed: 0.16, green: 0.62, blue: 0.98, alpha: 1)
        case .cpuFan:   return NSColor(srgbRed: 0.36, green: 0.78, blue: 0.55, alpha: 1)
        case .cpuFreq:  return NSColor(srgbRed: 0.55, green: 0.45, blue: 1.00, alpha: 1)
        case .cpuPower: return NSColor(srgbRed: 0.98, green: 0.62, blue: 0.16, alpha: 1)
        case .gpuTemp:  return NSColor(srgbRed: 0.95, green: 0.40, blue: 0.42, alpha: 1)
        case .gpuFan:   return NSColor(srgbRed: 0.45, green: 0.72, blue: 0.95, alpha: 1)
        }
    }

    /// 菜单栏上显示的紧凑文本（带单位缩写）
    func menuBarText(_ store: FanStore) -> String? {
        switch self {
        case .cpuTemp:
            return store.cpuTemp.map { String(format: "%.0f°", $0) }
        case .cpuFan:
            return store.cpuRPM > 0 ? "\(store.cpuRPM)" : nil
        case .cpuFreq:
            return store.freqGHz.map { String(format: "%.2fG", $0) }
        case .cpuPower:
            return store.powerWatts.map { String(format: "%.0fW", $0) }
        case .gpuTemp:
            return store.gpuTemp.map { String(format: "%.0f°", $0) }
        case .gpuFan:
            return store.gpuRPM > 0 ? "\(store.gpuRPM)" : nil
        }
    }

    /// 列表右侧显示的完整读数（带完整单位）
    func detailText(_ store: FanStore) -> String {
        switch self {
        case .cpuTemp:
            return store.cpuTemp.map { String(format: "%.0f °C", $0) } ?? "—"
        case .cpuFan:
            return store.cpuRPM > 0 ? "\(store.cpuRPM) RPM" : "—"
        case .cpuFreq:
            return store.freqGHz.map { String(format: "%.2f GHz", $0) } ?? "—"
        case .cpuPower:
            return store.powerWatts.map { String(format: "%.1f W", $0) } ?? "—"
        case .gpuTemp:
            return store.gpuTemp.map { String(format: "%.0f °C", $0) } ?? "—"
        case .gpuFan:
            return store.gpuRPM > 0 ? "\(store.gpuRPM) RPM" : "—"
        }
    }
}
