//
//  MenuBarSettingsView.swift
//  菜单栏设置：勾选、合并、拖动预览排序
//
//  排序：点「编辑顺序」→ 在预览条里拖动 chip →「保存顺序」。
//
//  为什么自己用 DragGesture 而不是 .onDrag/.onDrop：
//  系统拖拽会话结束时 AppKit 要把拖拽缩略图飞回去，SwiftUI 这边会留下残影，
//  松手瞬间也有一两帧的停顿。自己算位移则完全没有拖拽会话，松手就是一次纯数据更新。
//
//  选项列表顺序固定（MenuBarMetric.fixedOrder），拖动只改菜单栏排列。
//

import SwiftUI

struct MenuBarSettingsView: View {
    @ObservedObject var fan: FanStore
    @ObservedObject private var prefs = MenuBarPrefs.shared
    /// 返回设置页
    var onBack: () -> Void
    var onClose: () -> Void

    /// 编辑中的草稿：每个元素是一组 chip（普通指标 1 个成员，合并组 2 个）
    @State private var draft: [[MenuBarMetric]]?
    /// 编辑期间冻结的读数：2 秒一次的采样刷新会打断拖拽
    @State private var frozen: Snapshot?

    private var editing: Bool { draft != nil }

    private var groups: [[MenuBarMetric]] {
        draft ?? grouped(prefs.selected)
    }

    // MARK: 读数（编辑时用冻结值）

    private struct Snapshot {
        let menu: [MenuBarMetric: String]
        let detail: [MenuBarMetric: String]

        init(_ fan: FanStore) {
            var m: [MenuBarMetric: String] = [:]
            var d: [MenuBarMetric: String] = [:]
            for metric in MenuBarMetric.allCases {
                if let text = metric.menuBarText(fan) { m[metric] = text }
                d[metric] = metric.detailText(fan)
            }
            menu = m
            detail = d
        }
    }

    private func menuText(_ metric: MenuBarMetric) -> String? {
        frozen?.menu[metric] ?? metric.menuBarText(fan)
    }

    private func detailText(_ metric: MenuBarMetric) -> String {
        frozen?.detail[metric] ?? metric.detailText(fan)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            previewCard
            mergeToggle
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(MenuBarMetric.fixedOrder.enumerated()), id: \.element.id) { index, metric in
                        row(metric)
                        if index < MenuBarMetric.fixedOrder.count - 1 {
                            Divider().overlay(Palette.hairline)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.faintFill))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.cardStroke, lineWidth: 0.7))
                .padding(.bottom, 2)
            }
        }
        .padding(ModeBarStyle.padding)
        .frame(width: ModeBarStyle.windowWidth,
               height: ModeBarStyle.panelHeight,
               alignment: .topLeading)
        .background(Palette.bg)
    }

    // MARK: 头部

    private var header: some View {
        HStack {
            Text("菜单栏")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Palette.text)
            Spacer()
            Text(prefs.selected.isEmpty
                 ? "未显示指标"
                 : "\(prefs.selected.count)/\(MenuBarMetric.allCases.count) 已选")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textTertiary)
            Button {
                cancelEditing()
                onBack()
            } label: {
                Text("返回")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)

            Button {
                cancelEditing()
                onClose()
            } label: {
                Text("关闭")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .padding(.leading, 8)
        }
    }

    // MARK: 预览

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(editing ? "用箭头调整顺序" : "标题栏预览")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)

                Button {
                    if let draft {
                        save(draft)
                    } else {
                        startEditing()
                    }
                } label: {
                    Text(editing ? "保存顺序" : "编辑顺序")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(prefs.selected.isEmpty ? Palette.textTertiary : Palette.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(prefs.selected.isEmpty)

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: editing ? 6 : 10) {
                    if chipItems.isEmpty {
                        Text("未显示指标 —— 菜单栏会显示 D-helper")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    ForEach(Array(chipItems.enumerated()), id: \.element.id) { index, item in
                        if editing {
                            editableChip(item, at: index)
                        } else {
                            ChipLabel(item: item)
                        }
                    }
                }
                .frame(minWidth: 1)
            }
            .frame(height: 30)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(editing ? Palette.accent.opacity(0.08) : Palette.faintFill))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(editing ? Palette.accent.opacity(0.6) : Palette.cardStroke,
                              lineWidth: editing ? 1 : 0.7))
            // 关掉隐式动画：换位时不做过渡，避免留下残影
            .transaction { $0.animation = nil }
        }
    }

    // MARK: 编辑态 chip

    /// 编辑态的一个 chip：左右各一个箭头，点一次挪一格
    private func editableChip(_ item: ChipItem, at index: Int) -> some View {
        HStack(spacing: 1) {
            arrowButton(system: "chevron.left", enabled: index > 0) {
                moveChip(index, index - 1)
            }
            ChipLabel(item: item)
            arrowButton(system: "chevron.right", enabled: index < chipItems.count - 1) {
                moveChip(index, index + 1)
            }
        }
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Palette.accent.opacity(0.10))
        )
    }

    private func arrowButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(enabled ? Palette.accent : Palette.textTertiary.opacity(0.35))
                .frame(width: 15, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: chip 数据

    private var chipItems: [ChipItem] {
        groups.map { group in
            ChipItem(metrics: group, lines: chipLines(group), iconMetric: group[0])
        }
    }

    private func chipLines(_ group: [MenuBarMetric]) -> [String] {
        var top: String?
        var bottom: String?
        for metric in group {
            switch metric {
            case .cpuTemp, .gpuTemp:
                top = menuText(metric)
            case .cpuFan, .gpuFan:
                if let rpm = menuText(metric), let value = Int(rpm) {
                    bottom = MenuBarController.fanRPMText(value)
                } else {
                    bottom = menuText(metric)
                }
            default:
                return [menuText(metric)].compactMap { $0 }
            }
        }
        return [top, bottom].compactMap { $0 }
    }

    // MARK: 编辑态

    private func startEditing() {
        frozen = Snapshot(fan)
        draft = grouped(prefs.selected)
    }

    private func cancelEditing() {
        draft = nil
        frozen = nil
    }

    private func save(_ groups: [[MenuBarMetric]]) {
        prefs.setSelection(groups.flatMap { $0 })
        cancelEditing()
    }

    private func moveChip(_ from: Int, _ to: Int) {
        guard from != to, var working = draft,
              working.indices.contains(from), working.indices.contains(to) else { return }
        let item = working.remove(at: from)
        working.insert(item, at: to)
        draft = working
    }

    /// 按「合并」开关把勾选列表切成 chip 组
    private func grouped(_ metrics: [MenuBarMetric]) -> [[MenuBarMetric]] {
        var result: [[MenuBarMetric]] = []
        var emitted: Set<String> = []
        for metric in metrics {
            if prefs.mergeTemperatureAndFan {
                if metric == .cpuTemp || metric == .cpuFan {
                    if emitted.contains("cpu") { continue }
                    emitted.insert("cpu")
                    result.append([.cpuTemp, .cpuFan].filter { metrics.contains($0) })
                    continue
                }
                if metric == .gpuTemp || metric == .gpuFan {
                    if emitted.contains("gpu") { continue }
                    emitted.insert("gpu")
                    result.append([.gpuTemp, .gpuFan].filter { metrics.contains($0) })
                    continue
                }
            }
            result.append([metric])
        }
        return result
    }

    // MARK: 合并开关

    private var mergeToggle: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.1x2")
                .font(.system(size: 11))
                .foregroundStyle(prefs.mergeTemperatureAndFan ? Palette.accent : Palette.textTertiary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text("合并温度与转速")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.text)
                Text("CPU/GPU 各合成一组，温度在上、转速在下")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: Binding(get: { prefs.mergeTemperatureAndFan },
                                     set: { prefs.setMergeTemperatureAndFan($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Palette.accent)
                .disabled(editing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Palette.faintFill))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Palette.cardStroke, lineWidth: 0.7))
    }

    // MARK: 行（固定顺序）

    private func row(_ metric: MenuBarMetric) -> some View {
        let isOn = prefs.isOn(metric)
        return HStack(spacing: 8) {
            Group {
                if metric == .gpuTemp {
                    GPUCardGlyph(width: 13, height: 8.2,
                                 color: Color(nsColor: metric.tint),
                                 thermometer: true)
                } else {
                    Image(systemName: metric.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: metric.tint))
                }
            }
            .frame(width: 18, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(isOn ? Palette.text : Palette.textSecondary)
                Text(metric.source)
                    .font(.system(size: 8.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            Text(detailText(metric))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)

            Toggle("", isOn: Binding(get: { prefs.isOn(metric) },
                                     set: { prefs.set(metric, on: $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Palette.accent)
                // 编辑顺序时禁止改勾选，避免草稿和已保存状态打架
                .disabled(editing)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - chip 外观

struct ChipItem: Identifiable, Hashable {
    let metrics: [MenuBarMetric]
    let lines: [String]
    let iconMetric: MenuBarMetric

    var id: String { metrics.map(\.rawValue).joined(separator: "-") }
}

/// 一个 chip 的静态外观（图标 + 一到两行文字）
struct ChipLabel: View {
    let item: ChipItem

    var body: some View {
        HStack(spacing: 3) {
            Group {
                if item.iconMetric == .gpuTemp {
                    GPUCardGlyph(width: 13, height: 8.2,
                                 color: Color(nsColor: item.iconMetric.tint),
                                 thermometer: true)
                } else {
                    Image(systemName: item.iconMetric.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: item.iconMetric.tint))
                }
            }
            .frame(width: 16, alignment: .leading)

            if item.lines.count == 2 {
                VStack(alignment: .leading, spacing: -1) {
                    Text(item.lines[0])
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(item.lines[1])
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.textSecondary)
                }
            } else if let line = item.lines.first {
                Text(line)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Palette.text)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .fixedSize()
    }
}
