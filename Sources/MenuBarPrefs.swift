//
//  MenuBarPrefs.swift
//  菜单栏显示哪些指标、其顺序、是否合并温度与转速（持久化）
//

import Foundation
import Combine

final class MenuBarPrefs: ObservableObject {
    static let shared = MenuBarPrefs()

    /// 默认三项：温度 + 转速 + 功耗 —— 菜单栏宽度有限，默认别贪多
    private static let defaultSelection: [MenuBarMetric] = [.cpuTemp, .cpuFan, .cpuPower]
    private static let key = "menuBarMetrics"
    private static let mergeKey = "menuBarMerge"

    /// 用户勾选的指标，**数组顺序即菜单栏从左到右的顺序**。可以为空。
    @Published private(set) var selected: [MenuBarMetric]
    /// 把 CPU/GPU 的「温度 + 转速」各合并成一组，上下两行显示
    @Published private(set) var mergeTemperatureAndFan: Bool

    private init() {
        if let raw = UserDefaults.standard.array(forKey: Self.key) as? [String] {
            // 写过就以磁盘为准（哪怕写成了空数组，也代表"全不选"）
            selected = raw.compactMap(MenuBarMetric.init(rawValue:))
        } else {
            selected = Self.defaultSelection
        }
        mergeTemperatureAndFan = UserDefaults.standard.object(forKey: Self.mergeKey) as? Bool ?? false
    }

    func isOn(_ metric: MenuBarMetric) -> Bool {
        selected.contains(metric)
    }

    /// 允许全部取消：全不选时菜单栏显示默认托盘图标
    func set(_ metric: MenuBarMetric, on: Bool) {
        if on {
            guard !selected.contains(metric) else { return }
            selected.append(metric)          // 新勾选的排到末尾
        } else {
            selected.removeAll { $0 == metric }
        }
        persist()
    }

    /// 直接写入一整套顺序（预览里拖拽排序后保存用）
    func setSelection(_ metrics: [MenuBarMetric]) {
        // 去重但保留给定顺序
        var seen = Set<MenuBarMetric>()
        let cleaned = metrics.filter { seen.insert($0).inserted }
        guard cleaned != selected else { return }
        selected = cleaned
        persist()
    }

    func setMergeTemperatureAndFan(_ on: Bool) {
        mergeTemperatureAndFan = on
        UserDefaults.standard.set(on, forKey: Self.mergeKey)
    }

    private func persist() {
        UserDefaults.standard.set(selected.map(\.rawValue), forKey: Self.key)
    }
}
