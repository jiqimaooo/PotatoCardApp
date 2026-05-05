import ActivityKit
import SwiftUI
import WidgetKit

struct TransferActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let progress: Double
        let phaseTitle: String

        var percentText: String {
            "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
        }

        var isSucceeded: Bool {
            progress >= 1 || phaseTitle == "传输成功"
        }
    }

    let deviceName: String
}

struct TransferLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TransferActivityAttributes.self) { context in
            LockScreenTransferView(context: context)
                .activityBackgroundTint(Color.white)
                .activitySystemActionForegroundColor(AppColor.blue)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TransferFileIcon()
                        .frame(width: 38, height: 38)
                        .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.isSucceeded ? "传输完成" : "正在传输")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)

                        Text(context.attributes.deviceName)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    TransferProgressRing(progress: context.state.progress, lineWidth: 2.4)
                        .frame(width: 32, height: 32)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: min(max(context.state.progress, 0), 1))
                        .tint(AppColor.blue)
                }

            } compactLeading: {
                Image(systemName: "arrow.right.page.on.clipboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.blue)

            } compactTrailing: {
                TransferProgressRing(progress: context.state.progress, lineWidth: 2)
                    .frame(width: 16, height: 16)

            } minimal: {
                TransferProgressRing(progress: context.state.progress, lineWidth: 2)
                    .frame(width: 16, height: 16)
            }
        }
    }
}

private struct LockScreenTransferView: View {
    let context: ActivityViewContext<TransferActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            TransferFileIcon()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(context.state.phaseTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.09))

                Text(context.attributes.deviceName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.36, green: 0.36, blue: 0.38))
                    .lineLimit(1)

                ProgressView(value: min(max(context.state.progress, 0), 1))
                    .tint(AppColor.blue)
            }

            Spacer(minLength: 10)

            TransferProgressRing(
                progress: context.state.progress,
                backgroundColor: Color.black.opacity(0.12),
                lineWidth: 2.6
            )
            .frame(width: 38, height: 38)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private enum AppColor {
    static let blue = Color(red: 0.04, green: 0.45, blue: 1.0)
}

private struct TransferFileIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AppColor.blue)

            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5)
                .scaleEffect(0.72)

            Circle()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1.5)
                .scaleEffect(0.48)

            Image(systemName: "arrow.right.page.on.clipboard")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct TransferProgressRing: View {
    let progress: Double
    var backgroundColor: Color = Color.white.opacity(0.22)
    var lineWidth: CGFloat = 2.2

    private var safeProgress: Double {
        min(max(progress, 0.02), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(backgroundColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: safeProgress)
                .stroke(
                    AppColor.blue,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .padding(lineWidth / 2)
                .rotationEffect(.degrees(-90))

            if progress >= 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

@main
struct TransferLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        TransferLiveActivityWidget()
    }
}
