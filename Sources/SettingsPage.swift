//
//  SettingsPage.swift
//  设置页：挂在主窗口下的无边框面板（见 ChildPanel.swift）
//
//  内容区可滚动：面板高度固定（和主界面一致），条目变多也不改尺寸。
//

import SwiftUI
import AppKit

struct SettingsPage: View {
    @ObservedObject var fan: FanStore
    /// 关闭设置窗（由 SettingsPanel 注入）
    var onClose: () -> Void

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            // 面板高度固定，条目多了就在这里面滚
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    menuBarEntry
                    powerCard
                    samplingCard
                    versionCard
                    if let message = fan.message {
                        Text(message)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(ModeBarStyle.padding)
        .frame(width: ModeBarStyle.windowWidth,
               height: ModeBarStyle.panelHeight,
               alignment: .topLeading)
        .background(Palette.bg)
    }

    private var header: some View {
        HStack {
            Text("设置")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Palette.text)
            Spacer()
            Button {
                onClose()
            } label: {
                Text("关闭")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    // MARK: 菜单栏入口

    private var menuBarEntry: some View {
        Button {
            // 两个面板都是挂在主窗口下的子窗口，同时开会叠在一起，先收掉自己
            SettingsPanel.close()
            MenuBarPanel.show(relativeTo: nil)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 18)
                Text("菜单栏显示项")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 6)
                Text("\(MenuBarPrefs.shared.selected.count)/\(MenuBarMetric.allCases.count)")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(Palette.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.faintFill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.cardStroke, lineWidth: 0.7))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 开机相关

    private var powerCard: some View {
        card {
            // 开机自启
            HStack(spacing: 10) {
                Image(systemName: "power")
                    .font(.system(size: 13))
                    .foregroundStyle(launchAtLogin ? Palette.accent : Palette.textTertiary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("开机自启")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.text)
                    Text("登录时静默启动，不弹窗口；点程序坞图标打开界面。")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Toggle("", isOn: Binding(get: { launchAtLogin },
                                         set: { setLaunchAtLogin($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Palette.accent)
            }
            if let launchError {
                Text(launchError)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.bad)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Palette.hairline)

            // 开机自动恢复曲线
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(fan.autoRestoreEnabled ? Palette.accent : Palette.textTertiary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("重启后自动恢复曲线")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.text)
                    Text("EC 掉电会回到出厂曲线；由 root 守护进程在开机时重写上次下发的曲线。")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if fan.autoRestoreBusy {
                    ProgressView().controlSize(.mini).scaleEffect(0.75)
                } else {
                    Toggle("", isOn: Binding(get: { fan.autoRestoreEnabled },
                                             set: { fan.setAutoRestore($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .tint(Palette.accent)
                }
            }

            Text(restoreLine)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 采样间隔

    private var samplingCard: some View {
        card {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("采样间隔")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.text)
                    Text("温度、转速、频率与功耗的刷新节奏；改完立即生效。")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("曲线窗口 96 秒（\(fan.historyLimit) 点）")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    ForEach([1, 2, 3], id: \.self) { sec in
                        rateButton(sec)
                    }
                }
            }
        }
    }

    // MARK: 版本

    private var versionCard: some View {
        card {
            HStack {
                Text("版本")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 6)
                Text(Self.version)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Palette.text)
            }
        }
    }

    // MARK: 动作

    /// 开机自启：写/删 LaunchAgent，不需要 root
    private func setLaunchAtLogin(_ on: Bool) {
        launchError = nil
        if let error = LaunchAtLogin.set(on) {
            launchError = error
            launchAtLogin = LaunchAtLogin.isEnabled
        } else {
            launchAtLogin = on
        }
    }

    /// 直接取 Info.plist 的版本号，改版本时不用再改界面
    private static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    /// 守护进程状态 + 待恢复项，合并成一行
    private var restoreLine: String {
        var parts: [String] = []
        if fan.autoRestoreEnabled {
            parts.append(fan.autoRestoreInstalled ? "守护进程已安装" : "守护进程未安装")
        } else {
            parts.append("已关闭，切档位时不再安装")
        }
        if let state = FanStateStore.load() {
            let when = state.time.formatted(date: .abbreviated, time: .shortened)
            parts.append("待恢复：\(state.label) \(when)")
        } else {
            parts.append("暂无曲线记录")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: 组件

    private func rateButton(_ sec: Int) -> some View {
        let isOn = fan.samplingRate == sec
        return Button {
            fan.setSamplingRate(sec)
        } label: {
            Text("\(sec)s")
                .font(.system(size: 11, weight: isOn ? .semibold : .regular).monospacedDigit())
                .frame(width: 34, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? Palette.accent.opacity(0.15) : Palette.faintFill))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isOn ? Palette.accent : Palette.cardStroke,
                                  lineWidth: isOn ? 1.2 : 0.7))
                .foregroundStyle(isOn ? Palette.accent : Palette.textSecondary)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("每 \(sec) 秒采样一次")
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { content() }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.faintFill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.cardStroke, lineWidth: 0.7))
    }
}
