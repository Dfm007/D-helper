//
//  DHelperApp.swift
//  应用入口。入口链在 main.swift（要先把 CLI 参数分流掉）。
//

import SwiftUI
import AppKit

struct DHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("D-helper") {
            ModeBarView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 换过安装位置时，把开机自启指向新路径（否则登录时静默失败）
        LaunchAtLogin.repairIfMoved()

        // 菜单栏常驻项：即使主窗口被藏起来（开机自启），这里也始终有入口
        MainActor.assumeIsolated { MenuBarController.shared.start() }

        // 由开机自启拉起：不弹窗口，只驻留。点程序坞图标再打开界面。
        // 窗口是 SwiftUI 建的，出现时机不确定，所以收两次兜一下，避免登录时闪一下。
        if LaunchAtLogin.isAutostartLaunch {
            for delay in [0.15, 0.8] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    for w in NSApp.windows where w.frame.width > 300 {
                        w.orderOut(nil)
                    }
                }
            }
        }
    }

    /// 点程序坞图标时把主窗口叫回来。
    ///
    /// 注意返回值：`true` 表示"交给 AppKit 按默认方式处理"，而默认行为是
    /// 「看不到可见窗口就新建一个」—— 开机自启把窗口 orderOut 之后正好命中这条，
    /// 结果就是我这边调出了旧窗口、AppKit 又建了一个新的，变成两个窗口。
    /// 所以自己处理完必须返回 `false`。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag { return true }

        // 只认主窗口：设置窗是挂在主窗口下的无边框子窗口，parent 不为 nil
        if let main = sender.windows.first(where: { w in
            w.frame.width > 300 && w.parent == nil && !w.isVisible
        }) {
            main.makeKeyAndOrderFront(nil)
            return false
        }
        // 真的没有主窗口（用户点红灯关掉了），交给系统新建
        return true
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
