//
//  PowerFreqSection.swift
//  功能区：功耗与频率（真实读数）
//
//  标题行右侧只放当前值（4.82GHz 36W），不放「频率」「功耗」这类文字；
//  两个数字各用自己的曲线色，等于顺手当图例。
//
//  数据来自 FanStore：每 2 秒一点，48 点 = 96 秒窗口。
//  两条曲线各自归一化（频率 GHz 与功耗 W 量纲差一个数量级，共用一根轴会有一条被压平）。
//

import SwiftUI

// MARK: - 区块

struct PowerFreqSection: View {
    @ObservedObject var fan: FanStore

    private let freqColor = Palette.accent
    private let powerColor = Palette.warn

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            head
            chart
        }
    }

    // 图标 + 功耗与频率 ............ 4.82GHz 36W
    private var head: some View {
        HStack(spacing: 7) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 13)

            Text("功耗与频率")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.text)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Text(fan.freqGHz.map { String(format: "%.2fGHz", $0) } ?? "—")
                    .foregroundStyle(freqColor)
                Text(fan.powerWatts.map { String(format: "%.0fW", $0) } ?? "—")
                    .foregroundStyle(powerColor)
            }
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
        }
    }

    @ViewBuilder
    private var chart: some View {
        let hasData = fan.freqHistory.count >= 2 || fan.powerHistory.count >= 2
        Group {
            if hasData {
                PowerFreqChart(freq: fan.freqHistory,
                               power: fan.powerHistory,
                               freqColor: freqColor,
                               powerColor: powerColor)
            } else {
                // 起步阶段（或 kext 未加载）没有两个点，画不出线
                Text(fan.kextLoaded ? "采样中…" : "未读到 AMD 频率/功耗（AMDRyzenCPUPowerManagement 未加载）")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 108)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.faintFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.cardStroke, lineWidth: 0.7)
        )
    }
}

// MARK: - 曲线

struct PowerFreqChart: View {
    let freq: [Double]
    let power: [Double]
    let freqColor: Color
    let powerColor: Color

    /// 左右留白 / 上下留白（上下要多留，给最高最低值腾一行）
    private let insetX: CGFloat = 9
    private let insetY: CGFloat = 19

    private var freqMax: Double? { freq.max() }
    private var freqMin: Double? { freq.min() }
    private var powerMax: Double? { power.max() }
    private var powerMin: Double? { power.min() }

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let rect = CGRect(x: insetX, y: insetY,
                                  width: size.width - insetX * 2,
                                  height: size.height - insetY * 2)
                guard rect.width > 1, rect.height > 1 else { return }

                // 中间只留一条淡参考线；上下两条改成「极值参考线」（见下），不再重复画
                var mid = Path()
                let midY = rect.minY + rect.height * 0.5
                mid.move(to: CGPoint(x: rect.minX, y: midY))
                mid.addLine(to: CGPoint(x: rect.maxX, y: midY))
                ctx.stroke(mid, with: .color(Palette.cardStroke.opacity(0.45)), lineWidth: 0.5)

                // 最高 / 最低各一条贯穿全宽的参考线。
                // 两条序列是各自归一化的，所以「最高」都落在 rect.minY、「最低」都落在 rect.maxY，
                // 一条线同时服务频率和功耗 —— 这也是为什么线用中性色、只让文字带各自颜色。
                for y in [rect.minY, rect.maxY] {
                    var ref = Path()
                    ref.move(to: CGPoint(x: 0, y: y))
                    ref.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(ref, with: .color(Palette.textTertiary.opacity(0.45)), lineWidth: 0.6)
                }

                // 频率：线 + 淡淡的下方渐变
                if let pts = points(freq, in: rect) {
                    var line = Path()
                    line.addLines(pts)
                    var area = line
                    area.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    area.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                    area.closeSubpath()
                    ctx.fill(area, with: .linearGradient(
                        Gradient(colors: [freqColor.opacity(0.16), freqColor.opacity(0)]),
                        startPoint: CGPoint(x: 0, y: rect.minY),
                        endPoint: CGPoint(x: 0, y: rect.maxY)))
                    ctx.stroke(line, with: .color(freqColor),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }

                // 功耗：只画线，避免两层渐变糊在一起
                if let pts = points(power, in: rect) {
                    var line = Path()
                    line.addLines(pts)
                    ctx.stroke(line, with: .color(powerColor),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    if let last = pts.last {
                        let dot = Path(ellipseIn: CGRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4))
                        ctx.fill(dot, with: .color(powerColor))
                    }
                }
                if let pts = points(freq, in: rect), let last = pts.last {
                    let dot = Path(ellipseIn: CGRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4))
                    ctx.fill(dot, with: .color(freqColor))
                }
            }

            // 最高 / 最低：频率在左、功耗在右，各自用自己的曲线色
            VStack {
                HStack {
                    edgeLabel("↑", freqMax, isFreq: true)
                    Spacer(minLength: 6)
                    edgeLabel("↑", powerMax, isFreq: false)
                }
                Spacer(minLength: 0)
                HStack {
                    edgeLabel("↓", freqMin, isFreq: true)
                    Spacer(minLength: 6)
                    edgeLabel("↓", powerMin, isFreq: false)
                }
            }
            .padding(.horizontal, insetX)
            .padding(.vertical, 4)
        }
    }

    private func edgeLabel(_ arrow: String, _ value: Double?, isFreq: Bool) -> some View {
        HStack(spacing: 2) {
            Text(arrow)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isFreq ? freqColor.opacity(0.75) : powerColor.opacity(0.75))
            Text(value.map { isFreq ? String(format: "%.2fGHz", $0) : String(format: "%.0fW", $0) } ?? "—")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(isFreq ? freqColor.opacity(0.9) : powerColor.opacity(0.9))
        }
    }

    /// 每条序列按自身 min/max 归一化：频率和功耗量纲不同，共用坐标轴会有一条被压平
    private func points(_ series: [Double], in rect: CGRect) -> [CGPoint]? {
        guard series.count >= 2 else { return nil }
        let lo = series.min() ?? 0
        let hi = series.max() ?? 1
        let span = max(hi - lo, 0.0001)
        let stepX = rect.width / CGFloat(series.count - 1)
        return series.enumerated().map { i, v in
            let norm = (v - lo) / span
            return CGPoint(x: rect.minX + CGFloat(i) * stepX,
                           y: rect.maxY - CGFloat(norm) * rect.height)
        }
    }
}
