//
//  LaunchAtLogin.swift
//  开机自启：登录时静默拉起本 App（不弹窗口）
//
//  为什么不用 SMAppService.mainApp（macOS 13 起官方推荐）：
//  那套 API 要求应用被正式签名（Developer ID / 公证）并由 LaunchServices 正常注册；
//  本项目是 ad-hoc 签名，register() 会直接返回 "Operation not permitted"。
//
//  LaunchAgent 不挑签名，也不需要用户在「登录项」里额外批准：
//    · 打开：写 ~/Library/LaunchAgents/dev.dhelper.autostart.plist
//    · 关闭：删掉它，并 bootout 掉本次登录已加载的实例
//  写入后不 bootstrap —— RunAtLoad 会让 launchd 立刻再拉一份，变成开两个 App。
//

import Foundation

enum LaunchAtLogin {
    static let label = "dev.dhelper.autostart"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// 开关状态以 plist 是否存在为准
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// 本次启动是否由开机自启拉起（决定要不要把窗口藏起来）
    static var isAutostartLaunch: Bool {
        CommandLine.arguments.contains("--autostart")
    }

    /// 返回 nil 表示成功，否则是给用户看的错误说明
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        enabled ? enable() : disable()
    }

    /// App 改名 / 挪位置后，旧 plist 里的路径会指向不存在的包 → 登录时静默失败。
    /// 启动时对一遍：开关是开的但路径不对，就按当前位置重写。
    static func repairIfMoved() {
        guard isEnabled,
              let raw = try? String(contentsOf: plistURL, encoding: .utf8) else { return }
        let current = Bundle.main.bundlePath
        guard !raw.contains(xmlEscape(current)) else { return }
        _ = enable()
    }

    private static func enable() -> String? {
        let fm = FileManager.default
        let bundle = Bundle.main.bundlePath
        guard fm.fileExists(atPath: bundle) else {
            return "找不到应用包，无法设置开机自启"
        }

        let dir = plistURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return "无法创建 LaunchAgents 目录：\(error.localizedDescription)"
        }

        // 走 open 而不是直接指可执行文件：LaunchServices 负责激活与单实例，
        // -g 表示不要在登录时抢焦点
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-g</string>
                <string>-a</string>
                <string>\(xmlEscape(bundle))</string>
                <string>--args</string>
                <string>--autostart</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """
        do {
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "写入启动项失败：\(error.localizedDescription)"
        }
    }

    private static func disable() -> String? {
        try? FileManager.default.removeItem(at: plistURL)
        // 本次登录若已 load 过，顺手卸掉；失败无所谓 —— plist 没了，下次登录就不会启动
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return nil
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
