//
//  TransferProgressButton.swift
//  potato card
//
//  iOS 风格的“传输到设备”主操作按钮：
//  - 空闲态显示纯色填充胶囊按钮（保持苹果系强调色背景）；
//  - 传输/等待态时按钮自身变成进度条，左侧到右侧线性填充进度，
//    并把文字替换为“准备中…/传输中 xx%”，避免使用系统
//    `.borderedProminent` 在 disabled 时丢失背景色的问题。
//

import SwiftUI

/// 传输到设备主按钮：空闲时为强调色胶囊按钮；传输/等待时变成苹果风格的进度条按钮。
struct TransferProgressButton: View {
    /// 空闲时按钮上显示的文案。
    let idleTitle: String
    /// 传输中按钮上显示的前缀文案，最终会拼接 “xx%”。
    let inProgressTitle: String
    /// 当前传输进度，范围 [0, 1]。
    let progress: Double
    /// 是否处于传输/等待状态（决定是否显示进度条）。
    let isInProgress: Bool
    /// 是否允许点击（一般传 `activeDevice != nil`）。
    let isEnabled: Bool
    /// 点击空闲按钮时的回调。
    let action: () -> Void

    /// 整体高度。默认 50，与 `controlSize(.large)` 视觉一致。
    var height: CGFloat = 50
    /// 字号。
    var fontSize: CGFloat = 16
    /// 主色，默认跟随系统强调色，保证暗色模式自动适配。
    var tint: Color = .accentColor

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        // 传输中也禁止再次点击；同时不允许在没有设备时点击。
        .disabled(!isEnabled || isInProgress)
        .animation(.easeInOut(duration: 0.18), value: isInProgress)
        .animation(.linear(duration: 0.15), value: clampedProgress)
    }

    private var label: some View {
        let cornerRadius = height / 2
        let showsFill = isInProgress

        return ZStack(alignment: .leading) {
            // 底部胶囊：传输中调暗，作为进度条的“轨道”，避免点击区视觉消失。
            Capsule(style: .continuous)
                .fill(showsFill ? tint.opacity(0.28) : tint)

            if showsFill {
                GeometryReader { proxy in
                    // 复用按钮自身空间作为进度条，最小宽度等于胶囊高度，避免初始 0% 出现一个三角形。
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(
                            width: min(
                                proxy.size.width,
                                max(height, proxy.size.width * clampedProgress)
                            )
                        )
                }
                .allowsHitTesting(false)
            }

            Text(currentTitle)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: height)
        .clipShape(Capsule(style: .continuous))
        // 没设备但又不是传输中时整体淡化，提示不可点击；传输中保持满不透明，凸显进度。
        .opacity(isEnabled || isInProgress ? 1.0 : 0.4)
        .contentShape(Capsule(style: .continuous))
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var currentTitle: String {
        guard isInProgress else { return idleTitle }
        return "\(inProgressTitle) \(Int(clampedProgress * 100))%"
    }
}

#if DEBUG
#Preview("Idle") {
    TransferProgressButton(
        idleTitle: "传输到设备",
        inProgressTitle: "传输中",
        progress: 0,
        isInProgress: false,
        isEnabled: true,
        action: {}
    )
    .padding()
}

#Preview("In progress 42%") {
    TransferProgressButton(
        idleTitle: "传输到设备",
        inProgressTitle: "传输中",
        progress: 0.42,
        isInProgress: true,
        isEnabled: true,
        action: {}
    )
    .padding()
}

#Preview("Disabled (no device)") {
    TransferProgressButton(
        idleTitle: "传输到设备",
        inProgressTitle: "传输中",
        progress: 0,
        isInProgress: false,
        isEnabled: false,
        action: {}
    )
    .padding()
}
#endif
