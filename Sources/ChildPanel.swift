//
//  ChildPanel.swift
//  挂在主窗口下的无边框面板（设置窗、菜单栏窗共用）
//
//  为什么不用 sheet：sheet 是窗口模态，弹出时父窗口的红绿灯会被 AppKit 禁用。
//  这里用非模态子窗口模拟外观：贴在标题栏正下方，跟随主窗口移动，主窗口关闭时一起收起。
//

import SwiftUI
import AppKit

/// 无边框窗口默认 `canBecomeKey == false`：按钮要点两下、Esc 也不响应。这里放开。
final class BorderlessKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ChildPanel {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    /// 显示面板。每次都会重新构建内容并重新定位（主窗口可能已经移动过）。
    func show(view: AnyView,
              fallbackSize: CGSize,
              relativeTo parent: NSWindow?) {
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        let measured = hosting.fittingSize
        let size = (measured.width > 10 && measured.height > 10) ? measured : fallbackSize

        let win: NSWindow
        if let existing = window {
            win = existing
            win.contentView = hosting
            win.setContentSize(size)
        } else {
            win = BorderlessKeyWindow(contentRect: NSRect(origin: .zero, size: size),
                                      styleMask: [.borderless],
                                      backing: .buffered,
                                      defer: false)
            win.contentView = hosting
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = true
            win.isReleasedWhenClosed = false
            // 不能拖窗身：面板是主窗口的子窗口，跟着主窗口走就够了；
            // 允许拖的话会和内容里的滚动/点击抢事件
            win.isMovableByWindowBackground = false
            if let view = win.contentView {
                view.wantsLayer = true
                view.layer?.cornerRadius = 12
                // 只圆下面两个角：上沿贴着标题栏，看起来像从窗口里垂下来的 sheet
                view.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                view.layer?.masksToBounds = true
            }
            window = win
        }

        // 不能只靠 NSApp.keyWindow：点击瞬间它可能是 nil，那样会退化成屏幕居中
        if let host = parent ?? fallbackHost() {
            if win.parent !== host {
                win.parent?.removeChildWindow(win)
                host.addChildWindow(win, ordered: .above)
            }
            position(win, over: host)
            observeClose(of: host)
        } else {
            centerOnScreen(win)
        }
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        window?.orderOut(nil)
    }

    // MARK: 内部

    private func fallbackHost() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0 !== window && $0.parent == nil && $0.frame.width > 300 }
    }

    /// 贴在父窗口内容区顶部，水平居中。
    /// 不用 contentLayoutRect：它在布局未完成时会返回空矩形，算出来的原点会跑到屏幕左下角。
    private func position(_ win: NSWindow, over parent: NSWindow) {
        let pf = parent.frame
        let contentHeight = parent.contentView?.frame.height ?? pf.height
        let rawTitlebar = pf.height - contentHeight
        let titlebar = (rawTitlebar > 0 && rawTitlebar < 80) ? rawTitlebar : 28

        let size = win.frame.size
        win.setFrameOrigin(NSPoint(x: pf.midX - size.width / 2,
                                   y: pf.maxY - titlebar - size.height))
    }

    private func centerOnScreen(_ win: NSWindow) {
        guard let screen = NSScreen.main else { win.center(); return }
        let visible = screen.visibleFrame
        let size = win.frame.size
        win.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                   y: visible.midY - size.height / 2))
    }

    /// 主窗口被关闭时把面板一起收掉。只靠 addChildWindow 不够可靠：
    /// 子窗口被 orderOut 过之后，父子联动不一定还生效。
    private func observeClose(of host: NSWindow) {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: host,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }
}

// MARK: - 两个具体面板

@MainActor
enum SettingsPanel {
    static let panel = ChildPanel()

    static func show(relativeTo parent: NSWindow?) {
        panel.show(view: AnyView(SettingsPage(fan: FanStore.shared) { panel.close() }),
                   fallbackSize: CGSize(width: ModeBarStyle.windowWidth, height: ModeBarStyle.panelHeight),
                   relativeTo: parent)
    }

    static func close() { panel.close() }
}

@MainActor
enum MenuBarPanel {
    static let panel = ChildPanel()

    static func show(relativeTo parent: NSWindow?) {
        panel.show(view: AnyView(MenuBarSettingsView(
            fan: FanStore.shared,
            // 返回：先收掉自己，再把设置页弹回来
            onBack: {
                panel.close()
                SettingsPanel.show(relativeTo: parent)
            },
            onClose: { panel.close() }
        )),
                   fallbackSize: CGSize(width: ModeBarStyle.windowWidth, height: ModeBarStyle.panelHeight),
                   relativeTo: parent)
    }

    static func close() { panel.close() }
}
