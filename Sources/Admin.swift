//
//  Admin.swift
//  提权通道：写 SMC 必须 root，这里以管理员身份重跑自身 CLI
//
//  用 osascript 的 `do shell script ... with administrator privileges`：
//  只在那一下弹一次系统授权框，程序本身不常驻 root。
//

import Foundation

enum Admin {
    static var isRoot: Bool { geteuid() == 0 }

    /// 把提权失败的原始输出翻成人话。
    /// osascript 在用户点「取消」时返回的是 `execution error: User canceled. (-128)`，
    /// 直接拿这行字给用户看毫无意义。
    static func friendlyError(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if text.isEmpty { return "已取消授权，未做任何更改" }
        if text.contains("(-128)") || lower.contains("user canceled") || text.contains("用户已取消") {
            return "已取消授权，未做任何更改"
        }
        return text
    }

    /// 以管理员身份运行当前可执行文件的 CLI 模式
    static func runSelfAsAdmin(_ args: [String]) -> (ok: Bool, output: String) {
        if isRoot { return SelfExec.runCLI(args) }

        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let safePath = exe.replacingOccurrences(of: "\\", with: "\\\\")
                           .replacingOccurrences(of: "\"", with: "\\\"")
        let argString = args.joined(separator: " ")
        let script = "do shell script (quoted form of \"\(safePath)\") & \" \(argString)\" with administrator privileges"

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (p.terminationStatus == 0, out)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

/// 已经是 root 时直接在本进程内跑 CLI 逻辑
enum SelfExec {
    static func runCLI(_ args: [String]) -> (ok: Bool, output: String) {
        let status = CLI.run(args)
        return (status == 0, CLI.lastMessage)
    }
}
