//
//  main.swift
//  入口：带参数走 CLI（GUI 提权后重跑自己），否则起 GUI
//

import Foundation
import SwiftUI

let cliArgs = Array(CommandLine.arguments.dropFirst())

// 只画 UI 的离屏预览：--render <路径> [--dark] [settings]
if cliArgs.first == "--render" {
    guard cliArgs.count >= 2 else {
        print("ERR 用法: --render <输出路径> [--dark] [settings]")
        exit(2)
    }
    let which = cliArgs.contains("settings") ? "settings" : "main"
    var ok = false
    if #available(macOS 14.0, *) {
        ok = MainActor.assumeIsolated { PreviewRenderer.render(to: cliArgs[1], which: which) }
    }
    print(ok ? "OK 已渲染到 \(cliArgs[1])" : "ERR 渲染失败")
    exit(ok ? 0 : 6)
}

// 其余非选项参数按 CLI 处理：fan status / fan list / fan set <档位>
if let first = cliArgs.first, !first.hasPrefix("-") {
    exit(CLI.run(cliArgs))
}

DHelperApp.main()
