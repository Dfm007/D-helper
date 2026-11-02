//
//  MainWindow.swift
//  主窗口：自己持有 NSWindow，按需创建
//
//  为什么不用 SwiftUI 的 WindowGroup：
//    WindowGroup 在应用启动时就建好窗口并 orderFront，谁也拦不住。
//    开机自启想"不弹窗口"，只能在 didFinishLaunching 之后 orderOut —— 中间
//    至少已经渲染过一帧，用户看到的就是主界面一闪而过。
//    改成自己管窗口后，启动路径里根本没有"创建窗口"这一步，闪现从根上消失。
//
//  关闭后窗口对象保留（isReleasedWhenClosed = false），下次从菜单栏打开直接复用，
//  位置也会记住。
//

import AppKit
import SwiftUI

@MainActor
enum MainWindow {
    /// 关掉窗口只是 orderOut，对象一直在，用来复用和给子面板定位
    private static var window: NSWindow?

    /// 已存在的主窗口（可能当前不可见）。设置面板要挂在它下面。
    static var existing: NSWindow? { window }

    /// 打开主界面：没建过就建一个，建过就抬到最前
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        let win = window ?? make()
        window = win
        win.makeKeyAndOrderFront(nil)
    }

    private static func make() -> NSWindow {
        let size = NSSize(width: ModeBarStyle.windowWidth,
                          height: ModeBarStyle.panelHeight)
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered,
                           defer: false)
        win.title = "D-helper"
        // 关窗不销毁：否则再打开时 window 成了野指针，而且 SwiftUI 视图状态会重来一遍
        win.isReleasedWhenClosed = false
        win.contentViewController = NSHostingController(rootView: ModeBarView())
        win.setContentSize(size)
        // 位置按上次的恢复；首次启动没有记录就居中
        if !win.setFrameUsingName("D-helper") {
            win.center()
        }
        win.setFrameAutosaveName("D-helper")
        return win
    }
}
