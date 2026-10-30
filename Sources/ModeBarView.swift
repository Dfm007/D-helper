//
//  ModeBarView.swift
//  主界面：只有「模式」一行 + 4 个等宽按钮（G-Helper 风格）
//
//  读数来自 FanStore（真实 SMC 采样），点按钮直接下发对应档位曲线。
//

import SwiftUI

// MARK: - 样式（换配色 / 尺寸只改这里）

enum ModeBarStyle {
    static let windowWidth: CGFloat = 430
    /// 所有面板（主界面 / 设置 / 菜单栏）统一尺寸：
    /// 面板贴在标题栏下沿，高度和主界面内容区一致，看起来才像从窗口里垂下来。
    static let panelHeight: CGFloat = 352
    static let buttonHeight: CGFloat = 54
    static let corner: CGFloat = 8
    static let gap: CGFloat = 8
    static let padding: CGFloat = 16
}

// MARK: - 模式

enum ModeBarMode: String, CaseIterable, Identifiable {
    case silent, balanced, turbo, fanPower

    var id: String { rawValue }

    var title: String {
        switch self {
        case .silent:   return "静音"
        case .balanced: return "平衡"
        case .turbo:    return "增强"
        case .fanPower: return "自定义"
        }
    }

    var icon: String {
        switch self {
        case .silent:   return "moon.zzz.fill"
        case .balanced: return "car.side.fill"
        case .turbo:    return "flame.fill"
        case .fanPower: return "fanblades.fill"
        }
    }

    /// 每个模式自己的强调色：描边、图标、标题文字都用它
    var accent: Color {
        switch self {
        case .silent:   return Palette.ok      // 绿
        case .balanced: return Palette.accent  // 蓝
        case .turbo:    return Palette.bad     // 红
        case .fanPower: return Palette.violet  // 紫（未指定，先给一个中性色）
        }
    }

    /// 对应的风扇档位名（与 fan_presets.json 的 key 一致）。
    /// 自定义还没有实现，先不映射。
    var presetName: String? {
        switch self {
        case .silent:   return "silent"
        case .balanced: return "balanced"
        case .turbo:    return "performance"
        case .fanPower: return nil
        }
    }

    static func from(preset: String) -> ModeBarMode {
        switch preset {
        case "balanced":    return .balanced
        case "performance": return .turbo
        default:            return .silent
        }
    }
}

// MARK: - 界面

struct ModeBarView: View {
    @StateObject private var fan = FanStore.shared
    /// 承载本视图的 NSWindow（由 WindowBridge 报告），用来给设置窗定位
    @State private var hostWindow: NSWindow?

    /// 选中态完全来自 EC 回读；nil = 三档都不匹配（出厂曲线或别人写的自定义曲线）
    private var selected: ModeBarMode? {
        fan.current.map(ModeBarMode.from(preset:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            buttons
            PowerFreqSection(fan: fan)
                .padding(.top, 5)

            settingsRow

            // 下发失败 / 开机恢复安装失败的说明
            if let msg = fan.message {
                Text(msg)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.bad)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ModeBarStyle.padding)
        .frame(width: ModeBarStyle.windowWidth,
               height: ModeBarStyle.panelHeight,
               alignment: .top)
        .background(Palette.bg)
        .background(WindowBridge { win in
            if hostWindow !== win { hostWindow = win }
        })
        .onAppear { fan.start() }
    }

    /// 设置入口：贴着标题栏弹出设置窗（非模态，红绿灯不受影响）
    private var settingsRow: some View {
        Button {
            SettingsPanel.show(relativeTo: hostWindow)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 13)
                Text("设置")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.faintFill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.cardStroke, lineWidth: 0.7))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    //                                           CPU 71°C  风扇 6480 RPM
    // 模式: 静音                                  GPU 44°C  风扇 3660 RPM
    //   ↑ 左侧文字与 GPU 那行按基线对齐，CPU 自然落到上一行
    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: selected?.icon ?? "questionmark.circle")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(selected?.accent ?? Palette.textSecondary)
                    .frame(width: 13)

                Text("模式:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.text)

                Text(selected?.title ?? "未识别")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected?.accent ?? Palette.textSecondary)
            }

            Spacer(minLength: 8)

            // lastTextBaseline 取的是最后一个 Text 的基线 → 正好是 GPU 那行
            VStack(alignment: .trailing, spacing: 1) {
                Text(cpuStatusText)
                Text(gpuStatusText)
            }
            .font(.system(size: 10.5).monospacedDigit())
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
        }
    }

    private var buttons: some View {
        HStack(spacing: ModeBarStyle.gap) {
            ForEach(ModeBarMode.allCases) { mode in
                button(mode)
            }
        }
    }

    private func button(_ mode: ModeBarMode) -> some View {
        let isOn = (selected == mode)
        let busy = fan.applying == mode.presetName && fan.applying != nil
        return Button {
            // 自定义曲线还没做，点它目前不产生任何动作
            if let name = mode.presetName {
                fan.apply(name)
            }
        } label: {
            VStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                        .frame(height: 15)
                } else {
                    Image(systemName: mode.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(isOn ? mode.accent : Palette.textSecondary)
                        .frame(height: 15)
                }
                Text(mode.title)
                    .font(.system(size: 11, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Palette.text : Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: ModeBarStyle.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: ModeBarStyle.corner, style: .continuous)
                    .fill(isOn ? mode.accent.opacity(0.13) : Palette.faintFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ModeBarStyle.corner, style: .continuous)
                    .strokeBorder(isOn ? mode.accent : Palette.cardStroke,
                                  lineWidth: isOn ? 1.5 : 0.7)
            )
            .contentShape(RoundedRectangle(cornerRadius: ModeBarStyle.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(mode.title)
        .disabled(fan.applying != nil)
    }

    // MARK: 取值

    private var cpuStatusText: String {
        let temp = fan.cpuTemp.map { String(format: "%.0f°C", $0) } ?? "—"
        let rpm = fan.cpuRPM > 0 ? "\(fan.cpuRPM) RPM" : "—"
        return "CPU \(temp)  风扇 \(rpm)"
    }

    private var gpuStatusText: String {
        let temp = fan.gpuTemp.map { String(format: "%.0f°C", $0) } ?? "—"
        let rpm = fan.gpuRPM > 0 ? "\(fan.gpuRPM) RPM" : "—"
        return "GPU \(temp)  风扇 \(rpm)"
    }
}

/// 把承载视图的 NSWindow 报告给 SwiftUI 侧。
/// 比 `NSApp.keyWindow` 可靠：点击瞬间 keyWindow 可能是 nil，拿它定位会退化成"屏幕居中"。
struct WindowBridge: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}
