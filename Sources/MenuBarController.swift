//
//  MenuBarController.swift
//  菜单栏常驻项：图标 + 数值（可合并成两行）
//
//  样式按 macOS 菜单栏的通用规格来：
//    · 整段画成**模板图**（画黑色，isTemplate = true），由系统按菜单栏底色染色，
//      所以深色壁纸下是白的、浅色下是黑的，对比度始终正确
//    · 单行 12pt medium，合并两行 10.2pt bold，行间重叠 2.5pt
//    · 图标 10.5pt semibold；GPU 用自绘的「显卡卡片」图标
//    · 画布高 23，图标与文字间距 2，段间距 6
//
//  为什么不用 SwiftUI 的 MenuBarExtra：它的 label 只认单个 Text/Image，
//  图标 + 文字混排只会显示第一个。这里自己画一张图交给 NSStatusItem。
//

import AppKit
import Combine

@MainActor
final class MenuBarController {
    static let shared = MenuBarController()

    private var item: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    // 固定度量（菜单栏高度有限，这几项决定排版）
    private let textFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private let mergedFont = NSFont.monospacedDigitSystemFont(ofSize: 10.2, weight: .bold)
    private let iconPointSize: CGFloat = 10.5
    private let imageHeight: CGFloat = 23
    private let iconTextGap: CGFloat = 2
    private let segmentGap: CGFloat = 6
    private let blockOverlap: CGFloat = 2.5

    private init() {}

    /// 登录自启时，晚这么久再建状态项（见 start() 里的说明）
    private let loginInsertDelay: TimeInterval = 5
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        // 状态项的位置只由"创建顺序"决定：新建的总插在最左边，后来者把先来的往右挤。
        // 开机时我们起得早，之后 ChatGPT / BetterDisplay 这些登录项陆续起来，
        // 就一路把我们挤到右边去。所以登录这条路径上等它们上齐了再建，
        // 这样我们才是最左边那个。手动启动没有这个顾虑，立刻建。
        if LaunchAtLogin.isAutostartLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + loginInsertDelay) { [weak self] in
                self?.createStatusItem()
            }
        } else {
            createStatusItem()
        }

        // 读数每轮采样都会变；勾选/顺序也会变。两者都触发重画。
        // objectWillChange 在值写入之前发出，所以延后一拍再取新值。
        // 订阅先挂上没关系：状态项还没建时 refresh() 会自己跳过。
        FanStore.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &cancellables)

        MenuBarPrefs.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &cancellables)
    }

    private func createStatusItem() {
        guard item == nil else { return }

        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 有了 autosaveName，按住 ⌘ 拖动图标调整的位置才会被系统记住（下次启动还原）
        status.autosaveName = "dev.dhelper.status"
        status.button?.imagePosition = .imageOnly
        status.button?.target = self
        // 左键和右键都弹同一个菜单：只注册右键时左键点图标毫无反应，
        // 用户第一反应就是"点坏了"。这里两个键都发 action。
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        status.button?.action = #selector(statusItemClicked)
        status.button?.toolTip = "D-helper"
        item = status

        refresh()
    }

    func refresh() {
        guard let button = item?.button else { return }
        button.image = renderImage()
    }

    /// 左键 / 右键行为一致，都弹菜单，主界面从菜单里的「打开主界面」进。
    /// 应用现在是 Accessory（LSUIElement），程序坞没有图标、也没有主菜单栏，
    /// 所以「退出」只能放在这里，否则就没有入口了。
    @objc private func statusItemClicked() {
        showContextMenu()
    }

    @objc private func openMainWindow() {
        MainWindow.show()
    }

    @objc private func openSettings() {
        MainWindow.show()
        SettingsPanel.show(relativeTo: MainWindow.existing)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showContextMenu() {
        guard let button = item?.button else { return }
        let menu = NSMenu()

        let open = NSMenuItem(title: "打开主界面", action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 D-helper", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    // MARK: 画图

    private struct Segment {
        let icon: NSImage?
        let primary: NSAttributedString
        let secondary: NSAttributedString?

        var blockSize: NSSize {
            guard let secondary else { return primary.size() }
            let p = primary.size()
            let s = secondary.size()
            return NSSize(width: max(p.width, s.width), height: p.height + s.height - 2.5)
        }
        var iconSize: NSSize { icon?.size ?? .zero }
    }

    /// 把当前勾选的指标画成一张模板图（设置页的预览也用它）
    func renderImage() -> NSImage? {
        let segments = buildSegments()
        guard !segments.isEmpty else { return fallbackImage() }

        let contentWidth = segments.reduce(CGFloat.zero) { width, item in
            width + item.iconSize.width + iconTextGap + item.blockSize.width
        } + segmentGap * CGFloat(max(0, segments.count - 1))

        let size = NSSize(width: max(1, ceil(contentWidth)), height: imageHeight)
        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for (index, item) in segments.enumerated() {
                if let icon = item.icon {
                    icon.draw(in: NSRect(x: x,
                                         y: (self.imageHeight - item.iconSize.height) / 2,
                                         width: item.iconSize.width,
                                         height: item.iconSize.height),
                              from: .zero, operation: .sourceOver,
                              fraction: 1, respectFlipped: true, hints: nil)
                    x += item.iconSize.width + self.iconTextGap
                }

                let blockY = (self.imageHeight - item.blockSize.height) / 2
                if let secondary = item.secondary {
                    let primaryY = blockY + secondary.size().height - self.blockOverlap
                    item.primary.draw(at: NSPoint(x: x, y: primaryY))
                    secondary.draw(at: NSPoint(x: x, y: blockY))
                } else {
                    item.primary.draw(at: NSPoint(x: x, y: blockY))
                }
                x += item.blockSize.width
                if index < segments.count - 1 { x += self.segmentGap }
            }
            return true
        }
        // 模板图：系统按菜单栏外观统一染色，深色下自动变白
        image.isTemplate = true
        return image
    }

    // MARK: 组装

    private func buildSegments() -> [Segment] {
        let prefs = MenuBarPrefs.shared
        let store = FanStore.shared

        let regular: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: NSColor.black]
        let merged: [NSAttributedString.Key: Any] = [.font: mergedFont, .foregroundColor: NSColor.black]

        func attr(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
            NSAttributedString(string: text, attributes: attributes)
        }

        var result: [Segment] = []
        var emittedPair: Set<String> = []

        for metric in prefs.selected {
            // 合并模式：温度/转速成对出现，遇到第一个成员时整组吐出
            if prefs.mergeTemperatureAndFan {
                let isCPU = (metric == .cpuTemp || metric == .cpuFan)
                let isGPU = (metric == .gpuTemp || metric == .gpuFan)
                if isCPU || isGPU {
                    let key = isCPU ? "cpu" : "gpu"
                    if emittedPair.contains(key) { continue }
                    emittedPair.insert(key)

                    let pair: [MenuBarMetric] = isCPU ? [.cpuTemp, .cpuFan] : [.gpuTemp, .gpuFan]
                    var topText: String?
                    var bottomText: String?
                    for m in pair where prefs.isOn(m) {
                        if m == .cpuTemp || m == .gpuTemp {
                            topText = m.menuBarText(store)
                        } else if let rpm = m.menuBarText(store), let value = Int(rpm) {
                            bottomText = Self.fanRPMText(value)
                        } else {
                            bottomText = m.menuBarText(store)
                        }
                    }
                    guard topText != nil || bottomText != nil else { continue }
                    result.append(Segment(
                        icon: isCPU ? statusIcon(for: .cpuTemp) : gpuCardImage(thermometer: true),
                        primary: attr(topText ?? "", merged),
                        secondary: bottomText.map { attr($0, merged) }
                    ))
                    continue
                }
            }

            guard let text = metric.menuBarText(store) else { continue }
            result.append(Segment(icon: statusIcon(for: metric),
                                  primary: attr(text, regular),
                                  secondary: nil))
        }
        return result
    }

    /// 合并显示里转速那一行：4200 → "4200R"（原来是缩写 "4.2k"，用户嫌读不出原值）
    static func fanRPMText(_ rpm: Int) -> String {
        "\(rpm)R"
    }

    private func fallbackImage() -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        let text = NSAttributedString(string: "D-helper", attributes: attributes)
        let size = NSSize(width: ceil(text.size().width), height: imageHeight)
        let image = NSImage(size: size, flipped: false) { _ in
            text.draw(at: NSPoint(x: 0, y: (self.imageHeight - text.size().height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: 图标

    private func statusIcon(for metric: MenuBarMetric) -> NSImage? {
        switch metric {
        case .gpuTemp:
            return gpuCardImage(thermometer: true)
        default:
            let config = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .semibold)
            let base = NSImage(systemSymbolName: metric.icon, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            base?.isTemplate = true
            return base
        }
    }

    /// 自绘「显卡卡片」图标：圆角框 + 风扇圆 + 两条排线 + 金手指，
    /// 温度版在右上角叠一个极小的温度计。
    private func gpuCardImage(thermometer: Bool) -> NSImage {
        let width = iconPointSize * 1.35
        let height = iconPointSize * 0.82
        let extra: CGFloat = thermometer ? 6 : 0

        let image = NSImage(size: NSSize(width: width + extra, height: imageHeight),
                            flipped: false) { _ in
            let cardY = (self.imageHeight - height) / 2
            let cardRect = NSRect(x: 0, y: cardY, width: width, height: height)
            NSColor.black.setStroke()

            let card = NSBezierPath(roundedRect: cardRect, xRadius: 2.2, yRadius: 2.2)
            card.lineWidth = 1.15
            card.stroke()

            let fanDiameter = height * 0.44
            let fanRect = NSRect(x: cardRect.minX + 2.4,
                                 y: cardRect.midY - fanDiameter / 2,
                                 width: fanDiameter, height: fanDiameter)
            let fan = NSBezierPath(ovalIn: fanRect)
            fan.lineWidth = 0.95
            fan.stroke()

            let bars = NSBezierPath()
            bars.lineWidth = 1.0
            bars.move(to: NSPoint(x: cardRect.maxX - width * 0.35, y: cardRect.midY + 1.2))
            bars.line(to: NSPoint(x: cardRect.maxX - width * 0.10, y: cardRect.midY + 1.2))
            bars.move(to: NSPoint(x: cardRect.maxX - width * 0.32, y: cardRect.midY - 0.9))
            bars.line(to: NSPoint(x: cardRect.maxX - width * 0.14, y: cardRect.midY - 0.9))
            bars.stroke()

            let connector = NSRect(x: cardRect.midX - width * 0.19,
                                   y: cardRect.minY - 1.1,
                                   width: width * 0.38, height: 1.2)
            NSColor.black.setFill()
            NSBezierPath(rect: connector).fill()

            if thermometer,
               let symbol = NSImage(systemSymbolName: "thermometer.medium",
                                    accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 5.8, weight: .bold)) {
                symbol.isTemplate = true
                symbol.draw(in: NSRect(x: width + 0.8,
                                       y: cardRect.maxY - 4.8,
                                       width: 5.8, height: 5.8),
                            from: .zero, operation: .sourceOver,
                            fraction: 1, respectFlipped: true, hints: nil)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
