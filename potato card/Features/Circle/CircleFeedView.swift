import SwiftUI
import UIKit

private struct CircleFeedScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum CircleFeedScrollCoordinateSpace {
    static let name = "circle-feed-scroll"
}

struct CircleFeedView: View {
    let posts: [CirclePost]
    let onTransfer: (CirclePost) -> Void
    let onReport: (CirclePost) -> Void
    let onRefresh: () -> Void
    let onScrollOffsetChange: (CGFloat) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            CircleFeedScrollOffsetReader()

            if posts.isEmpty {
                CircleEmptyFeedView()
            } else {
                HStack(alignment: .top, spacing: 10) {
                    CircleMasonryColumn(
                        posts: columns.left,
                        onTransfer: onTransfer,
                        onReport: onReport
                    )
                    CircleMasonryColumn(
                        posts: columns.right,
                        onTransfer: onTransfer,
                        onReport: onReport
                    )
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .coordinateSpace(name: CircleFeedScrollCoordinateSpace.name)
        .background(CircleFeedStyle.pageBackground)
        .onPreferenceChange(CircleFeedScrollOffsetPreferenceKey.self, perform: onScrollOffsetChange)
        .refreshable {
            onRefresh()
        }
    }

    private var columns: (left: [CirclePost], right: [CirclePost]) {
        var left: [CirclePost] = []
        var right: [CirclePost] = []
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 0

        for post in posts {
            let estimatedHeight = CircleFeedStyle.previewHeight(for: post) + 82
            if leftHeight <= rightHeight {
                left.append(post)
                leftHeight += estimatedHeight
            } else {
                right.append(post)
                rightHeight += estimatedHeight
            }
        }

        return (left, right)
    }
}

struct CircleDriftBottleView: View {
    let posts: [CirclePost]
    let onTransfer: (CirclePost) -> Void
    let onThrow: () -> Void
    let onRefresh: () -> Void
    let onScrollOffsetChange: (CGFloat) -> Void

    @State private var selectedPostID: String?
    @State private var isDrawingBottle = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                CircleFeedScrollOffsetReader()

                if posts.isEmpty {
                    CircleDriftBottleEmptyView()
                        .frame(minHeight: proxy.size.height)
                } else if let selectedPost {
                    VStack(spacing: 14) {
                        CircleDriftBottleCard(
                            post: selectedPost,
                            isDrawing: isDrawingBottle,
                            onTransfer: {
                                guard !isDrawingBottle else { return }
                                onTransfer(selectedPost)
                            }
                        )
                        .id(selectedPost.id)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            )
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)

                        CircleDriftBottleDrawAgainButton(
                            isDrawing: isDrawingBottle,
                            onDraw: drawNextBottle
                        )
                    }
                    .frame(minHeight: max(0, proxy.size.height - 32))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                } else {
                    CircleDriftBottleStartView(
                        isDrawing: isDrawingBottle,
                        onThrow: onThrow,
                        onStart: drawNextBottle
                    )
                    .frame(minHeight: max(0, proxy.size.height - 32))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .refreshable {
                onRefresh()
            }
            .coordinateSpace(name: CircleFeedScrollCoordinateSpace.name)
            .onPreferenceChange(CircleFeedScrollOffsetPreferenceKey.self, perform: onScrollOffsetChange)
        }
        .background(CircleFeedStyle.pageBackground)
        .animation(.spring(response: 0.46, dampingFraction: 0.86), value: selectedPostID)
        .onAppear(perform: ensureSelectedPost)
        .onChange(of: posts) { _ in
            ensureSelectedPost()
        }
    }

    private var selectedPost: CirclePost? {
        guard let selectedPostID else { return nil }
        return posts.first(where: { $0.id == selectedPostID })
    }

    private func ensureSelectedPost() {
        guard !posts.isEmpty else {
            selectedPostID = nil
            isDrawingBottle = false
            return
        }
        if let currentSelectedPostID = selectedPostID,
           !posts.contains(where: { $0.id == currentSelectedPostID }) {
            selectedPostID = nil
        }
    }

    private func selectRandomPost() {
        guard !posts.isEmpty else {
            selectedPostID = nil
            return
        }

        if posts.count == 1 {
            selectedPostID = posts[0].id
            return
        }

        let currentID = selectedPostID
        let candidates = posts.filter { $0.id != currentID }
        selectedPostID = (candidates.randomElement() ?? posts.randomElement())?.id
    }

    private func drawNextBottle() {
        guard !isDrawingBottle else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            isDrawingBottle = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.76) {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) {
                selectRandomPost()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                withAnimation(.easeOut(duration: 0.24)) {
                    isDrawingBottle = false
                }
            }
        }
    }
}

private struct CircleFeedScrollOffsetReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: CircleFeedScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named(CircleFeedScrollCoordinateSpace.name)).minY
                )
        }
        .frame(height: 1)
        .padding(.bottom, -1)
    }
}

private struct CircleDriftBottleStartView: View {
    @Environment(\.colorScheme) private var colorScheme

    let isDrawing: Bool
    let onThrow: () -> Void
    let onStart: () -> Void

    var body: some View {
        ZStack {
            if isDrawing {
                CircleDriftBottleLoadingOverlay()
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            } else {
                VStack(spacing: 26) {
                    Spacer(minLength: 0)

                    CircleDriftBottleOceanSVGView(colorScheme: colorScheme)
                        .frame(height: 230)
                        .frame(maxWidth: 340)
                        .accessibilityHidden(true)

                    Button(action: onThrow) {
                        Label("扔一个", systemImage: "paperplane.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(CircleFeedStyle.driftTint)
                            .frame(width: 168, height: 48)
                            .background(
                                CircleFeedStyle.driftTint.opacity(0.10),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(CircleFeedStyle.driftTint.opacity(0.18), lineWidth: 0.8)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isDrawing)

                    Button(action: onStart) {
                        Label("开始捞", systemImage: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                            .frame(width: 168, height: 52)
                            .background(CircleFeedStyle.driftTint, in: Capsule())
                            .shadow(color: CircleFeedStyle.driftTint.opacity(0.26), radius: 18, x: 0, y: 10)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isDrawing)
    }
}

private struct CircleDriftBottleOceanSVGView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let colorScheme: ColorScheme

    private let canvasSize = CGSize(width: 360, height: 230)

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { proxy in
                let scale = min(proxy.size.width / canvasSize.width, proxy.size.height / canvasSize.height)
                let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

                oceanScene(phase: phase)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .scaleEffect(scale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func oceanScene(phase: TimeInterval) -> some View {
        let colors = palette

        return ZStack {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [colors.skyTop.opacity(0.92), colors.skyBottom.opacity(0.50)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 324, height: 206)
                .position(x: 180, y: 113)

            Circle()
                .fill(colors.sun.opacity(0.72))
                .frame(width: 48, height: 48)
                .position(x: 286, y: 54)

            cloudPath
                .stroke(colors.cloud.opacity(0.32), style: StrokeStyle(lineWidth: 12, lineCap: .round))

            bubblePair(
                phase: phase,
                duration: 4.6,
                delay: 0,
                opacity: 0.50,
                first: CGPoint(x: 78, y: 144),
                firstRadius: 5,
                second: CGPoint(x: 94, y: 126),
                secondRadius: 3,
                colors: colors
            )

            bubblePair(
                phase: phase,
                duration: 5.3,
                delay: 0.7,
                opacity: 0.42,
                first: CGPoint(x: 286, y: 154),
                firstRadius: 4,
                second: CGPoint(x: 266, y: 137),
                secondRadius: 2.5,
                colors: colors
            )

            bubblePair(
                phase: phase,
                duration: 4.9,
                delay: 1.2,
                opacity: 0.38,
                first: CGPoint(x: 132, y: 164),
                firstRadius: 3.5,
                second: CGPoint(x: 222, y: 142),
                secondRadius: 3,
                colors: colors
            )

            Group {
                waveA
                    .fill(
                        LinearGradient(
                            colors: [colors.seaLeft, colors.seaMid, colors.seaRight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(0.76)
                    .offset(
                        x: CGFloat(oscillation(phase, duration: 7.4, low: -18, high: 16)),
                        y: CGFloat(oscillation(phase, duration: 7.4, low: 0, high: -5))
                    )

                waveB
                    .fill(colors.waveMid)
                    .opacity(0.82)
                    .offset(
                        x: CGFloat(oscillation(phase, duration: 6.2, low: 14, high: -20)),
                        y: CGFloat(oscillation(phase, duration: 6.2, low: 1, high: -7))
                    )

                waveC
                    .fill(colors.waveFront)
                    .opacity(0.92)
                    .offset(
                        x: CGFloat(oscillation(phase, duration: 8.2, low: -10, high: 22)),
                        y: CGFloat(oscillation(phase, duration: 8.2, low: 0, high: -4))
                    )
            }
            .shadow(color: colors.shadow.opacity(0.22), radius: 12, x: 0, y: 14)

            bottle(phase: phase, colors: colors)

            foamPathA
                .stroke(colors.foam.opacity(0.54), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            foamPathB
                .stroke(colors.foam.opacity(0.48), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }

    private var palette: OceanPalette {
        if colorScheme == .dark {
            return OceanPalette(
                skyTop: Color(red: 0.06, green: 0.13, blue: 0.22),
                skyBottom: Color(red: 0.09, green: 0.18, blue: 0.27),
                seaLeft: Color(red: 0.11, green: 0.43, blue: 0.62),
                seaMid: Color(red: 0.14, green: 0.59, blue: 0.79),
                seaRight: Color(red: 0.34, green: 0.80, blue: 0.90),
                waveMid: Color(red: 0.08, green: 0.42, blue: 0.60),
                waveFront: Color(red: 0.04, green: 0.30, blue: 0.49),
                foam: Color(red: 0.84, green: 0.97, blue: 1.00),
                glass: Color(red: 0.49, green: 0.85, blue: 0.95),
                cloud: Color(red: 0.78, green: 0.93, blue: 1.00),
                sun: Color(red: 0.47, green: 0.84, blue: 1.00),
                shadow: Color(red: 0.02, green: 0.07, blue: 0.12),
                cork: Color(red: 0.66, green: 0.52, blue: 0.34),
                note: Color(red: 0.97, green: 0.95, blue: 0.91)
            )
        }

        return OceanPalette(
            skyTop: Color(red: 0.91, green: 0.97, blue: 1.00),
            skyBottom: .white,
            seaLeft: Color(red: 0.65, green: 0.91, blue: 0.96),
            seaMid: Color(red: 0.27, green: 0.74, blue: 0.91),
            seaRight: Color(red: 0.04, green: 0.49, blue: 0.76),
            waveMid: Color(red: 0.15, green: 0.62, blue: 0.85),
            waveFront: Color(red: 0.03, green: 0.44, blue: 0.71),
            foam: .white,
            glass: Color(red: 0.56, green: 0.87, blue: 0.95),
            cloud: Color(red: 0.55, green: 0.81, blue: 0.92),
            sun: Color(red: 1.00, green: 0.88, blue: 0.54),
            shadow: Color(red: 0.04, green: 0.30, blue: 0.47),
            cork: Color(red: 0.71, green: 0.55, blue: 0.34),
            note: Color(red: 1.00, green: 0.97, blue: 0.87)
        )
    }

    private var cloudPath: Path {
        Path { path in
            path.move(to: CGPoint(x: 72, y: 64))
            path.addCurve(to: CGPoint(x: 186, y: 68), control1: CGPoint(x: 110, y: 44), control2: CGPoint(x: 151, y: 46))
            path.addCurve(to: CGPoint(x: 291, y: 70), control1: CGPoint(x: 220, y: 89), control2: CGPoint(x: 254, y: 90))
        }
    }

    private var foamPathA: Path {
        Path { path in
            path.move(to: CGPoint(x: 60, y: 134))
            path.addCurve(to: CGPoint(x: 152, y: 136), control1: CGPoint(x: 92, y: 123), control2: CGPoint(x: 122, y: 124))
        }
    }

    private var foamPathB: Path {
        Path { path in
            path.move(to: CGPoint(x: 210, y: 158))
            path.addCurve(to: CGPoint(x: 306, y: 160), control1: CGPoint(x: 242, y: 147), control2: CGPoint(x: 276, y: 148))
        }
    }

    private var waveA: Path {
        Path { path in
            path.move(to: CGPoint(x: -40, y: 130))
            path.addCurve(to: CGPoint(x: 96, y: 130), control1: CGPoint(x: 8, y: 104), control2: CGPoint(x: 48, y: 104))
            path.addCurve(to: CGPoint(x: 232, y: 130), control1: CGPoint(x: 144, y: 156), control2: CGPoint(x: 184, y: 156))
            path.addCurve(to: CGPoint(x: 400, y: 132), control1: CGPoint(x: 280, y: 104), control2: CGPoint(x: 322, y: 104))
            path.addLine(to: CGPoint(x: 400, y: 224))
            path.addLine(to: CGPoint(x: -40, y: 224))
            path.closeSubpath()
        }
    }

    private var waveB: Path {
        Path { path in
            path.move(to: CGPoint(x: -46, y: 152))
            path.addCurve(to: CGPoint(x: 104, y: 152), control1: CGPoint(x: 6, y: 124), control2: CGPoint(x: 54, y: 124))
            path.addCurve(to: CGPoint(x: 250, y: 152), control1: CGPoint(x: 154, y: 180), control2: CGPoint(x: 201, y: 180))
            path.addCurve(to: CGPoint(x: 406, y: 151), control1: CGPoint(x: 299, y: 124), control2: CGPoint(x: 336, y: 124))
            path.addLine(to: CGPoint(x: 406, y: 224))
            path.addLine(to: CGPoint(x: -46, y: 224))
            path.closeSubpath()
        }
    }

    private var waveC: Path {
        Path { path in
            path.move(to: CGPoint(x: -46, y: 173))
            path.addCurve(to: CGPoint(x: 108, y: 173), control1: CGPoint(x: 8, y: 145), control2: CGPoint(x: 56, y: 145))
            path.addCurve(to: CGPoint(x: 258, y: 173), control1: CGPoint(x: 160, y: 201), control2: CGPoint(x: 208, y: 201))
            path.addCurve(to: CGPoint(x: 406, y: 174), control1: CGPoint(x: 308, y: 145), control2: CGPoint(x: 344, y: 146))
            path.addLine(to: CGPoint(x: 406, y: 224))
            path.addLine(to: CGPoint(x: -46, y: 224))
            path.closeSubpath()
        }
    }

    private func bubblePair(
        phase: TimeInterval,
        duration: Double,
        delay: Double,
        opacity: Double,
        first: CGPoint,
        firstRadius: CGFloat,
        second: CGPoint,
        secondRadius: CGFloat,
        colors: OceanPalette
    ) -> some View {
        let progress = bubbleProgress(phase, duration: duration, delay: delay)
        let yOffset = 26 - (66 * progress)
        let scale = 0.72 + (0.32 * progress)
        let fadeIn = min(progress / 0.35, 1)
        let fadeOut = min(max((1 - progress) / 0.65, 0), 1)
        let alpha = opacity * min(fadeIn, fadeOut)

        return ZStack {
            Circle()
                .fill(colors.foam)
                .frame(width: firstRadius * 2, height: firstRadius * 2)
                .position(first)

            Circle()
                .fill(colors.foam.opacity(0.72))
                .frame(width: secondRadius * 2, height: secondRadius * 2)
                .position(second)
        }
        .offset(y: CGFloat(yOffset))
        .scaleEffect(CGFloat(scale))
        .opacity(alpha)
    }

    private func bottle(phase: TimeInterval, colors: OceanPalette) -> some View {
        let drift = oscillation(phase, duration: 3.7, low: 0, high: 1)
        let glint = oscillation(phase, duration: 2.8, low: 0.28, high: 0.9)
        let x = 190 + (10 * drift)
        let y = 132 - (10 * drift)
        let rotation = -31 + (15 * drift)

        return ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.86), colors.glass.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 82)
                .overlay {
                    Capsule()
                        .stroke(colors.foam.opacity(0.68), lineWidth: 1.2)
                }
                .position(x: 25, y: 59)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(colors.cork)
                .frame(width: 16, height: 28)
                .position(x: 25, y: 14)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(colors.note.opacity(0.92))
                .frame(width: 20, height: 20)
                .position(x: 25, y: 72)

            Capsule()
                .fill(.white.opacity(glint))
                .frame(width: 3, height: 47)
                .offset(x: CGFloat(oscillation(phase, duration: 2.8, low: -3, high: 5)))
                .position(x: 19, y: 55)
        }
        .frame(width: 50, height: 110)
        .rotationEffect(.degrees(rotation))
        .position(x: CGFloat(x), y: CGFloat(y))
    }

    private func bubbleProgress(_ phase: TimeInterval, duration: Double, delay: Double) -> Double {
        ((phase + delay).truncatingRemainder(dividingBy: duration)) / duration
    }

    private func oscillation(_ phase: TimeInterval, duration: Double, low: Double, high: Double) -> Double {
        guard !reduceMotion else { return (low + high) / 2 }
        let normalized = (sin((phase / duration) * .pi * 2) + 1) / 2
        return low + ((high - low) * normalized)
    }

    private struct OceanPalette {
        let skyTop: Color
        let skyBottom: Color
        let seaLeft: Color
        let seaMid: Color
        let seaRight: Color
        let waveMid: Color
        let waveFront: Color
        let foam: Color
        let glass: Color
        let cloud: Color
        let sun: Color
        let shadow: Color
        let cork: Color
        let note: Color
    }
}

private struct CircleDriftBottleDrawAgainButton: View {
    let isDrawing: Bool
    let onDraw: () -> Void

    var body: some View {
        Button(action: onDraw) {
            Label(isDrawing ? "正在打捞" : "再捞一个", systemImage: isDrawing ? "sparkles" : "shuffle")
                .font(.system(size: 14, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(CircleFeedStyle.driftTint)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    CircleFeedStyle.driftTint.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(CircleFeedStyle.driftTint.opacity(0.16), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDrawing)
    }
}

private struct CircleDriftBottleCard: View {
    let post: CirclePost
    let isDrawing: Bool
    let onTransfer: () -> Void

    private var seed: Int {
        CircleFeedStyle.seed(for: "drift-bottle-" + post.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTransfer) {
                CircleDriftBottleDevicePreview(post: post, seed: seed)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 430, maxHeight: .infinity)
                    .layoutPriority(1)
                    .scaleEffect(isDrawing ? 0.98 : 1)
                    .blur(radius: isDrawing ? 2 : 0)
            }
            .buttonStyle(.plain)
            .disabled(isDrawing)
            .accessibilityLabel("传输漂流瓶图片")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
        .background(CircleFeedStyle.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CircleFeedStyle.hairline, lineWidth: 0.8)
        }
        .overlay {
            if isDrawing {
                CircleDriftBottleLoadingOverlay()
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 9)
        .animation(.easeInOut(duration: 0.22), value: isDrawing)
    }
}

private struct CircleDriftBottleLoadingOverlay: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            CircleFeedStyle.driftTint.opacity(0.22),
                            Color(.systemBackground).opacity(0.36),
                            CircleFeedStyle.driftTint.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 14) {
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(CircleFeedStyle.driftTint.opacity(0.28 - Double(index) * 0.06), lineWidth: 1.2)
                            .frame(width: 70 + CGFloat(index) * 34, height: 70 + CGFloat(index) * 34)
                            .scaleEffect(isAnimating ? 1.16 : 0.86)
                            .opacity(isAnimating ? 0.14 : 0.42)
                            .animation(
                                .easeInOut(duration: 1.05)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.14),
                                value: isAnimating
                            )
                    }

                    CircleDriftBottleGlyph()
                        .rotationEffect(.degrees(isAnimating ? 9 : -9))
                        .offset(y: isAnimating ? -6 : 6)
                        .shadow(color: CircleFeedStyle.driftTint.opacity(0.24), radius: 18, x: 0, y: 10)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isAnimating)
                }
                .frame(width: 170, height: 138)

                VStack(spacing: 8) {
                    Text("正在打捞新的漂流瓶")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(CircleFeedStyle.driftTint)
                                .frame(width: 5, height: 5)
                                .scaleEffect(isAnimating ? 1 : 0.55)
                                .opacity(isAnimating ? 1 : 0.42)
                                .animation(
                                    .easeInOut(duration: 0.55)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.12),
                                    value: isAnimating
                                )
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

private struct CircleDriftBottleGlyph: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.78),
                            CircleFeedStyle.driftTint.opacity(0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 42, height: 104)
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.62), lineWidth: 1)
                }
                .rotationEffect(.degrees(-28))

            Capsule()
                .fill(Color(red: 0.72, green: 0.56, blue: 0.34))
                .frame(width: 18, height: 34)
                .offset(x: 32, y: -40)
                .rotationEffect(.degrees(-28))

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.86))
                .frame(width: 38, height: 18)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(CircleFeedStyle.driftTint.opacity(0.20), lineWidth: 1)
                }
                .offset(x: -2, y: 12)
                .rotationEffect(.degrees(-28))
        }
    }
}

private struct CircleDriftBottleDevicePreview: View {
    let post: CirclePost
    let seed: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CircleFeedStyle.driftPreviewBackground)

            screenPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack {
                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "lock.display")
                        .font(.system(size: 12, weight: .semibold))

                    Text("点击传输以查看")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.primary.opacity(0.74))
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var screenPreview: some View {
        if let previewUrl = post.previewUrl {
            CircleCachedPreviewImage(
                cacheKey: "drift-bottle-" + post.id,
                url: previewUrl,
                seed: seed
            )
        } else {
            CircleFeedAbstractArtwork(seed: seed)
        }
    }
}

private struct CircleMasonryColumn: View {
    let posts: [CirclePost]
    let onTransfer: (CirclePost) -> Void
    let onReport: (CirclePost) -> Void

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(posts) { post in
                CirclePostCard(
                    post: post,
                    onTransfer: { onTransfer(post) },
                    onReport: { onReport(post) }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CirclePostCard: View {
    let post: CirclePost
    let onTransfer: () -> Void
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            lockedPreview

            VStack(alignment: .leading, spacing: 7) {
                Text(post.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !post.tags.isEmpty {
                    Text(post.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CircleFeedStyle.tint.opacity(0.85))
                        .lineLimit(1)
                }

                authorAndTransferRow

            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 9)
        }
        .background(CircleFeedStyle.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CircleFeedStyle.hairline, lineWidth: 0.5)
        }
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button(role: .destructive, action: onReport) {
                Label("举报", systemImage: "exclamationmark.bubble")
            }
        }
    }

    private var lockedPreview: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: CircleFeedStyle.palette(for: post),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let previewUrl = post.previewUrl {
                    CircleCachedPreviewImage(
                        cacheKey: post.id,
                        url: previewUrl,
                        seed: CircleFeedStyle.seed(for: post)
                    )
                } else {
                    CircleFeedAbstractArtwork(seed: CircleFeedStyle.seed(for: post))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: CircleFeedStyle.previewHeight(for: post))
            .overlay {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.28)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: "lock.display")
                            .font(.system(size: 18, weight: .semibold))
                        Text("点击传输以查看")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 3)
                    .padding(10)
                }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var authorAndTransferRow: some View {
        HStack(spacing: 6) {
            CircleAvatarView(
                username: post.author.username,
                avatarKey: post.author.avatarKey,
                avatarUrl: post.author.avatarUrl
            )

            Text(post.author.username)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            transferTextButton
        }
    }

    private var transferTextButton: some View {
        Button(action: onTransfer) {
            Label("传输", systemImage: "paperplane.fill")
                .font(.system(size: 10, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(CircleFeedStyle.tint)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(CircleFeedStyle.tint.opacity(0.10), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(CircleFeedStyle.tint.opacity(0.18), lineWidth: 0.7)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("传输 \(post.title)")
    }

}

private struct CircleCachedPreviewImage: View {
    let cacheKey: String
    let url: URL
    let seed: Int

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    CircleServerPreviewImage(image: Image(uiImage: image))
                } else {
                    CircleFeedAbstractArtwork(seed: seed)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: url) { _ in
            loadIfNeeded()
        }
    }

    private func loadIfNeeded() {
        guard !isLoading else { return }
        isLoading = true

        let cacheKey = cacheKey
        let url = url

        Task {
            if let cachedImage = await CircleImageDiskCache.shared.image(for: cacheKey, kind: .preview) {
                await MainActor.run {
                    image = cachedImage
                    isLoading = false
                }
                return
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard
                    let httpResponse = response as? HTTPURLResponse,
                    (200..<300).contains(httpResponse.statusCode),
                    let loadedImage = UIImage(data: data)
                else {
                    await MainActor.run { isLoading = false }
                    return
                }

                CircleImageDiskCache.shared.set(loadedImage, data: data, for: cacheKey, kind: .preview)
                await MainActor.run {
                    image = loadedImage
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

private struct CircleServerPreviewImage: View {
    let image: Image

    var body: some View {
        image
            .resizable()
            .scaledToFill()
            .scaleEffect(1.06)
            .blur(radius: 14, opaque: true)
            .saturation(0.9)
            .contrast(0.94)
            .overlay(Color.white.opacity(0.1))
            .overlay(Color.black.opacity(0.12))
            .clipped()
    }
}

private struct CircleCachedAvatarImage: View {
    let cacheKey: String
    let url: URL

    @State private var image: UIImage?
    @State private var isLoading = false

    init(cacheKey: String, url: URL) {
        self.cacheKey = cacheKey
        self.url = url
        _image = State(initialValue: CircleImageDiskCache.shared.cachedImage(for: cacheKey, kind: .avatar))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                EmptyView()
            }
        }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: url) { _ in
            loadIfNeeded()
        }
    }

    private func loadIfNeeded() {
        guard !isLoading else { return }
        isLoading = true

        let cacheKey = cacheKey
        let url = url

        Task {
            if let cachedImage = await CircleImageDiskCache.shared.image(for: cacheKey, kind: .avatar) {
                await MainActor.run {
                    image = cachedImage
                    isLoading = false
                }
                return
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard
                    let httpResponse = response as? HTTPURLResponse,
                    (200..<300).contains(httpResponse.statusCode),
                    let loadedImage = UIImage(data: data)
                else {
                    await MainActor.run { isLoading = false }
                    return
                }

                CircleImageDiskCache.shared.set(loadedImage, data: data, for: cacheKey, kind: .avatar)
                await MainActor.run {
                    image = loadedImage
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

private final class CircleImageDiskCache: @unchecked Sendable {
    static let shared = CircleImageDiskCache()

    enum CacheKind {
        case preview
        case avatar

        var directoryName: String {
            switch self {
            case .preview:
                return "previews"
            case .avatar:
                return "avatars"
            }
        }

        var memoryPrefix: String {
            switch self {
            case .preview:
                return "preview"
            case .avatar:
                return "avatar"
            }
        }
    }

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.xiaogousi.potatocard.circle-image-cache", qos: .utility)
    private let previewLimitBytes: UInt64 = 5 * 1024 * 1024 * 1024
    private let previewTargetBytes: UInt64 = 4 * 1024 * 1024 * 1024
    private let rootURL: URL

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 120 * 1024 * 1024

        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        rootURL = supportURL.appendingPathComponent("PotatoCircleImages", isDirectory: true)
        createDirectoryIfNeeded(directoryURL(for: .preview))
        createDirectoryIfNeeded(directoryURL(for: .avatar))
        excludeFromBackup(rootURL)
        migrateLegacyCacheIfNeeded()
    }

    func image(for key: String, kind: CacheKind) async -> UIImage? {
        let memoryKey = memoryKey(for: key, kind: kind)
        if let memoryImage = cache.object(forKey: memoryKey as NSString) {
            return memoryImage
        }

        return await withCheckedContinuation { continuation in
            ioQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                let fileURL = self.fileURL(for: key, kind: kind)
                guard
                    let data = try? Data(contentsOf: fileURL),
                    let image = UIImage(data: data)
                else {
                    continuation.resume(returning: nil)
                    return
                }

                self.touch(fileURL)
                self.cache.setObject(image, forKey: memoryKey as NSString, cost: self.memoryCost(for: image))
                continuation.resume(returning: image)
            }
        }
    }

    func cachedImage(for key: String, kind: CacheKind) -> UIImage? {
        let memoryKey = memoryKey(for: key, kind: kind)
        if let memoryImage = cache.object(forKey: memoryKey as NSString) {
            return memoryImage
        }

        let fileURL = fileURL(for: key, kind: kind)
        guard
            let data = try? Data(contentsOf: fileURL),
            let image = UIImage(data: data)
        else {
            return nil
        }

        touch(fileURL)
        cache.setObject(image, forKey: memoryKey as NSString, cost: memoryCost(for: image))
        return image
    }

    func set(_ image: UIImage, data: Data, for key: String, kind: CacheKind) {
        let memoryKey = memoryKey(for: key, kind: kind)
        let shouldTrimPreviewCache = kind == .preview
        cache.setObject(image, forKey: memoryKey as NSString, cost: memoryCost(for: image))

        ioQueue.async { [weak self] in
            guard let self else { return }
            let directoryURL = self.directoryURL(for: kind)
            self.createDirectoryIfNeeded(directoryURL)

            do {
                try data.write(to: self.fileURL(for: key, kind: kind), options: [.atomic])
                if shouldTrimPreviewCache {
                    self.trimPreviewCacheIfNeeded()
                }
            } catch {
                return
            }
        }
    }

    private func memoryCost(for image: UIImage) -> Int {
        let pixelCount = Int(image.size.width * image.scale * image.size.height * image.scale)
        return pixelCount * 4
    }

    private func memoryKey(for key: String, kind: CacheKind) -> String {
        "\(kind.memoryPrefix):\(key)"
    }

    private func directoryURL(for kind: CacheKind) -> URL {
        rootURL.appendingPathComponent(kind.directoryName, isDirectory: true)
    }

    private func fileURL(for key: String, kind: CacheKind) -> URL {
        directoryURL(for: kind).appendingPathComponent(fileName(for: key), isDirectory: false)
    }

    private func fileName(for key: String) -> String {
        key.utf8.map { String(format: "%02x", $0) }.joined() + ".img"
    }

    private func createDirectoryIfNeeded(_ url: URL) {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func excludeFromBackup(_ url: URL) {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(resourceValues)
    }

    private func migrateLegacyCacheIfNeeded() {
        guard let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }

        let legacyRootURL = cachesURL.appendingPathComponent("PotatoCircleImages", isDirectory: true)
        guard legacyRootURL.path != rootURL.path else { return }

        migrateLegacyDirectory(from: legacyRootURL.appendingPathComponent(CacheKind.preview.directoryName, isDirectory: true), to: directoryURL(for: .preview))
        migrateLegacyDirectory(from: legacyRootURL.appendingPathComponent(CacheKind.avatar.directoryName, isDirectory: true), to: directoryURL(for: .avatar))
    }

    private func migrateLegacyDirectory(from sourceURL: URL, to targetURL: URL) {
        guard let files = try? fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil) else {
            return
        }

        createDirectoryIfNeeded(targetURL)
        for sourceFileURL in files {
            let targetFileURL = targetURL.appendingPathComponent(sourceFileURL.lastPathComponent, isDirectory: false)
            guard !fileManager.fileExists(atPath: targetFileURL.path) else { continue }
            try? fileManager.copyItem(at: sourceFileURL, to: targetFileURL)
        }
    }

    private func touch(_ url: URL) {
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func trimPreviewCacheIfNeeded() {
        let directoryURL = directoryURL(for: .preview)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let entries: [(url: URL, size: UInt64, date: Date)] = files.compactMap { url in
            guard
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                let size = values.fileSize,
                let date = values.contentModificationDate
            else {
                return nil
            }
            return (url, UInt64(size), date)
        }

        var totalSize = entries.reduce(UInt64(0)) { $0 + $1.size }
        guard totalSize > previewLimitBytes else { return }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard totalSize > previewTargetBytes else { break }
            try? fileManager.removeItem(at: entry.url)
            totalSize = totalSize > entry.size ? totalSize - entry.size : 0
        }
    }
}

private struct CircleFeedAbstractArtwork: View {
    let seed: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: proxy.size.width * 0.58, height: proxy.size.width * 0.58)
                    .offset(x: proxy.size.width * offsetA, y: -proxy.size.height * 0.18)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: proxy.size.width * 0.64, height: proxy.size.height * 0.42)
                    .rotationEffect(.degrees(Double(seed % 18) - 9))
                    .offset(x: -proxy.size.width * 0.16, y: proxy.size.height * 0.16)

                Capsule()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: proxy.size.width * 0.45, height: 12)
                    .offset(x: proxy.size.width * 0.08, y: proxy.size.height * 0.26)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var offsetA: CGFloat {
        seed.isMultiple(of: 2) ? 0.18 : -0.14
    }
}

private struct CircleAvatarView: View {
    let username: String
    let avatarKey: String
    let avatarUrl: URL?

    var body: some View {
        ZStack {
            placeholder

            if let avatarUrl {
                CircleCachedAvatarImage(cacheKey: avatarKey, url: avatarUrl)
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(Circle())
    }

    private var initial: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0) } ?? "土"
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: CircleFeedStyle.avatarPalette(seed: CircleFeedStyle.seed(for: avatarKey)),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(initial)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct CircleEmptyFeedView: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CircleFeedStyle.tint.opacity(0.10))
                    .frame(width: 76, height: 76)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(CircleFeedStyle.tint)
            }

            VStack(spacing: 6) {
                Text("还没有圈子作品")
                    .font(.system(size: 18, weight: .semibold))
                Text("发布第一张照片，让其他人传输到土豆片查看。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 120)
    }
}

struct CircleUnavailableFeedView: View {
    let title: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 76, height: 76)

                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                Text("\(title)暂未开放")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("先去发现里看看大家传来的照片。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .background(CircleFeedStyle.pageBackground)
    }
}

private struct CircleDriftBottleEmptyView: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CircleFeedStyle.driftTint.opacity(0.10))
                    .frame(width: 76, height: 76)

                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(CircleFeedStyle.driftTint)
            }

            VStack(spacing: 6) {
                Text("还没有漂来的照片")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("发现里有作品后，漂流瓶会随机抽一张给你。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 120)
    }
}

private enum CircleFeedStyle {
    static let tint = Color(red: 0.86, green: 0.16, blue: 0.22)
    static let driftTint = Color(red: 0.08, green: 0.48, blue: 0.86)
    static let pageBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let hairline = Color.primary.opacity(0.07)
    static let driftPreviewBackground = Color(.tertiarySystemGroupedBackground)

    static func seed(for post: CirclePost) -> Int {
        seed(for: post.id + post.title + post.author.username)
    }

    static func seed(for text: String) -> Int {
        var value: UInt32 = 2_166_136_261
        for scalar in text.unicodeScalars {
            value = (value ^ UInt32(scalar.value)) &* 16_777_619
        }
        return Int(value % 10_000)
    }

    static func previewHeight(for post: CirclePost) -> CGFloat {
        let heights: [CGFloat] = [138, 166, 194, 222]
        return heights[seed(for: post) % heights.count]
    }

    static func palette(for post: CirclePost) -> [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.86, green: 0.79, blue: 0.69), Color(red: 0.48, green: 0.62, blue: 0.52), Color(red: 0.20, green: 0.30, blue: 0.25)],
            [Color(red: 0.90, green: 0.78, blue: 0.80), Color(red: 0.62, green: 0.52, blue: 0.58), Color(red: 0.30, green: 0.28, blue: 0.32)],
            [Color(red: 0.86, green: 0.88, blue: 0.90), Color(red: 0.55, green: 0.63, blue: 0.68), Color(red: 0.33, green: 0.38, blue: 0.42)],
            [Color(red: 0.93, green: 0.88, blue: 0.75), Color(red: 0.70, green: 0.55, blue: 0.30), Color(red: 0.40, green: 0.31, blue: 0.18)]
        ]
        return palettes[seed(for: post) % palettes.count]
    }

    static func avatarPalette(seed: Int) -> [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.94, green: 0.66, blue: 0.58), Color(red: 0.82, green: 0.23, blue: 0.32)],
            [Color(red: 0.56, green: 0.68, blue: 0.58), Color(red: 0.25, green: 0.46, blue: 0.36)],
            [Color(red: 0.72, green: 0.62, blue: 0.86), Color(red: 0.38, green: 0.34, blue: 0.72)],
            [Color(red: 0.78, green: 0.62, blue: 0.38), Color(red: 0.46, green: 0.32, blue: 0.18)]
        ]
        return palettes[seed % palettes.count]
    }
}
