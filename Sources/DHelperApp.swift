//
//  DHelperApp.swift
//  应用入口。入口链在 main.swift（要先把 CLI 参数分流掉）。
//

import SwiftUI
import AppKit

struct DHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // 主窗口由 MainWindow 自己建（见 MainWindow.swift），这里只留一个不出窗口的
        // Settings 场景占位：SwiftUI 的 App 至少要有一个 Scene，而 WindowGroup
        // 会在启动时立刻弹窗 —— 那正是开机自启「一闪而过」的来源。
        // 顺便把系统自带的「设置…」菜单项去掉，那个空窗口没有任何用处。
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {}
                CommandGroup(replacing: .newItem) {}
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 换过安装位置时，把开机自启指向新路径（否则登录时静默失败）
        LaunchAtLogin.repairIfMoved()

        // 采样必须在这里启动：开机自启不再建窗口，菜单栏读数不能指望
        // ModeBarView.onAppear 来拉起采样循环。
        FanStore.shared.start()

        // 菜单栏常驻项：主窗口开不开，这里都是唯一入口
        MainActor.assumeIsolated { MenuBarController.shared.start() }

        // 由开机自启拉起：到此为止，不建窗口。
        // 以前是先让 WindowGroup 建好窗口再 orderOut，中间已经渲染过一帧，
        // 于是每次开机都能看到主界面闪一下。
        guard !LaunchAtLogin.isAutostartLaunch else { return }

        MainActor.assumeIsolated { MainWindow.show() }
    }

    /// 点程序坞图标 / 在访达里双击（此时窗口多半是关掉的）时把主窗口叫回来。
    ///
    /// 注意返回值：`true` 表示"交给 AppKit 按默认方式处理"，而默认行为是
    /// 「看不到可见窗口就新建一个」—— 我们自己的窗口对象还在，走默认就会多出一个。
    /// 所以自己处理完必须返回 `false`。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag { return true }
        MainActor.assumeIsolated { MainWindow.show() }
        return false
    }

    /// 设置窗是无边框子窗口；默认退出流程会先去关窗口，可能被它牵制。
    /// 这里直接放行，程序坞右键「退出」立刻生效。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }
}

enum PreviewRenderer {
    @MainActor
    static func render(to path: String, which: String = "main") -> Bool {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let dark = CommandLine.arguments.contains("--dark")
        if let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) {
            app.appearance = appearance
        }

        let content: AnyView = which == "settings"
            ? AnyView(SettingsPage(fan: FanStore.shared) {})
            : AnyView(ModeBarView())

        func draw() -> Bool {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2.0
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return false }
            return (try? png.write(to: URL(fileURLWithPath: path))) != nil
        }

        // Palette 用 NSColor 动态色，要让它按指定外观求值，
        // 否则离屏渲染会一律按当前系统外观解析
        if let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) {
            var ok = false
            appearance.performAsCurrentDrawingAppearance { ok = draw() }
            return ok
        }
        return draw()
    }
}
