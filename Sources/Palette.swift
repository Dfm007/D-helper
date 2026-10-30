//
//  Palette.swift
//  最小配色集：只留跑通这一屏需要的几个语义色，深浅色自适应
//

import SwiftUI
import AppKit

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0,
                  alpha: 1)
    }
}

extension Color {
    /// 给一个浅色值 + 深色值，跟随系统外观自动切换
    static func adaptive(_ light: UInt32, _ dark: UInt32,
                         lightOpacity: CGFloat = 1, darkOpacity: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
                .withAlphaComponent(isDark ? darkOpacity : lightOpacity)
        })
    }
}

enum Palette {
    // 背景
    static let bg = Color.adaptive(0xF1F3F7, 0x0B0D10)
    static let bgSoft = Color.adaptive(0xFFFFFF, 0x14171C)

    // 强调（选中描边 / 高亮数值）
    static let accent = Color.adaptive(0x007AFF, 0x0A84FF)

    // 模式色：静音绿 / 平衡蓝 / 增强红 / 自定义紫
    static let ok = Color.adaptive(0x1DA45F, 0x2FD57C)
    static let bad = Color.adaptive(0xD62A3C, 0xFF3B4E)
    static let violet = Color.adaptive(0x7C5CFF, 0xA78BFA)

    // 功耗曲线用橙
    static let warn = Color.adaptive(0xC77F00, 0xFFB020)

    // 文字
    static let text = Color.adaptive(0x1B2331, 0xE9F0FA)
    static let textSecondary = Color.adaptive(0x52627A, 0xA3B2C6)
    static let textTertiary = Color.adaptive(0x8B98AB, 0x6C7C92)

    // 描边 / 填充
    static let cardStroke = Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.11, darkOpacity: 0.10)
    static let faintFill = Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.06, darkOpacity: 0.07)
    static let hairline = Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.10, darkOpacity: 0.08)
}
