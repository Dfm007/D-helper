//
//  GPUCardGlyph.swift
//  显卡卡片图标（SwiftUI 版）：圆角框 + 风扇圆 + 两条排线 + 金手指，
//  温度版右上角叠一个很小的温度计。
//
//  菜单栏里那份是 Core Graphics 画的（MenuBarController.gpuCardImage），
//  这里是给设置页列表用的 SwiftUI 版本，形状保持一致。
//

import SwiftUI

struct GPUCardGlyph: View {
    var width: CGFloat = 16
    var height: CGFloat = 10
    var color: Color = .primary
    var thermometer = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                    .stroke(color, lineWidth: 1.15)
                    .frame(width: width, height: height)

                HStack(spacing: 2) {
                    Circle()
                        .stroke(color, lineWidth: 0.95)
                        .frame(width: height * 0.42, height: height * 0.42)
                    VStack(spacing: 1.0) {
                        Capsule().fill(color).frame(width: width * 0.28, height: 1.0)
                        Capsule().fill(color).frame(width: width * 0.22, height: 1.0)
                    }
                }

                Rectangle()
                    .fill(color)
                    .frame(width: width * 0.38, height: 1.1)
                    .offset(y: height * 0.62)
            }

            if thermometer {
                ZStack {
                    Circle()
                        .fill(Palette.bg)
                        .frame(width: 8, height: 8)
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 5.8, weight: .bold))
                        .foregroundStyle(color)
                }
                .offset(x: 5, y: -5)
            }
        }
        .frame(width: thermometer ? width + 6 : width,
               height: thermometer ? height + 5 : height)
    }
}
