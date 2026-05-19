//
//  GalleryShareFlow.swift
//  potato card
//
//  长按相册照片 → 分享到圈子 / 分享到漂流瓶 的容器。
//
//  - GalleryShareDestination: 区分两条分享链路。
//  - GallerySharePreparer: 给一张图 + 一份 EInkManualAdjustment 渲染 400×600 JPEG。
//  - GalleryShareSheet: 入口；负责三段式状态机 — 未登录注册 → 交互式裁切 → 发布。
//  - GalleryShareAdjustmentView: 400×600 canvas 上的可交互裁切 + 滑块，
//    与 InteractiveDevicePreview 同源的几何与手势，但画布严格按上传比例显示，
//    用户看到的就是真正会传给服务端的内容。
//

import Foundation
import SwiftUI
import UIKit

enum GalleryShareDestination: Identifiable {
    case circle(photo: GalleryPhoto)
    case driftBottle(photo: GalleryPhoto)

    var id: String {
        switch self {
        case .circle(let photo):
            return "circle:\(photo.id.uuidString)"
        case .driftBottle(let photo):
            return "drift:\(photo.id.uuidString)"
        }
    }

    var photo: GalleryPhoto {
        switch self {
        case .circle(let photo), .driftBottle(let photo):
            return photo
        }
    }

    var navigationTitle: String {
        switch self {
        case .circle:
            return "分享到圈子"
        case .driftBottle:
            return "扔进漂流瓶"
        }
    }

    var continueButtonTitle: String {
        switch self {
        case .circle:
            return "下一步"
        case .driftBottle:
            return "下一步"
        }
    }
}

enum GallerySharePreparer {
    // 圈子 / 漂流瓶服务端约定的画布尺寸：与土豆片墨水屏 400×600 主屏一致，
    // 这样发布作品时其他用户拉到的图直接就能走「传输到设备」管线，无需再二次裁切。
    static let shareCanvasSize = CGSize(width: 400, height: 600)
    private static let shareJPEGCompressionQuality: CGFloat = 0.85

    // 按调用方传入的 EInkManualAdjustment 渲染 400×600 JPEG。
    // 与 EInkImageRenderer.render 完全同源，所以「裁切 UI 看到的画面」≡
    // 「上传给服务端的画面」≡「最终别人传到墨水屏的画面」。
    static func renderShareImageData(
        for image: UIImage,
        adjustment: EInkManualAdjustment
    ) -> Data? {
        let fitMode: EInkImageFitMode = .manual
        let rendered = EInkImageRenderer.render(
            image: image,
            targetSize: shareCanvasSize,
            fitMode: fitMode,
            adjustment: adjustment
        )
        return rendered.jpegData(compressionQuality: shareJPEGCompressionQuality)
    }
}

// MARK: - Share Sheet Container

struct GalleryShareSheet: View {
    let destination: GalleryShareDestination
    let onPublishSucceeded: ((GalleryShareDestination) -> Void)?
    let onPublishFailed: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var sessionStore = CircleSessionStore()
    // 三段式状态机：
    //   nil       → 还在「调整」步骤，让用户拖拽 / 缩放 / 旋转。
    //   非 nil    → 已经渲染好 400×600 数据，切到「发布」步骤的 composer。
    @State private var preparedImageData: Data?
    private let apiClient = GalleryShareSheet.defaultAPIClient()

    init(
        destination: GalleryShareDestination,
        onPublishSucceeded: ((GalleryShareDestination) -> Void)? = nil,
        onPublishFailed: ((String) -> Void)? = nil
    ) {
        self.destination = destination
        self.onPublishSucceeded = onPublishSucceeded
        self.onPublishFailed = onPublishFailed
    }

    var body: some View {
        Group {
            if !sessionStore.isRegistered {
                // 阶段 1：未登录 → 先走注册 / 登录视图。
                // 登录成功后 isRegistered 切到 true，自动进入阶段 2。
                CircleRegistrationView(sessionStore: sessionStore, apiClient: apiClient)
            } else if preparedImageData == nil {
                // 阶段 2：交互式 400×600 裁切。点「下一步」后渲染出 JPEG。
                GalleryShareAdjustmentView(
                    photo: destination.photo,
                    destination: destination,
                    onContinue: { renderedData in
                        // SwiftUI 不会因为闭包结尾的赋值产生额外动画，主动加 animation 让两步切换更顺滑。
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            preparedImageData = renderedData
                        }
                    }
                )
            } else if let imageData = preparedImageData {
                // 阶段 3：复用 Circle 现有 composer，传入预渲染好的 400×600 数据。
                publishContent(imageData: imageData)
            }
        }
        .onAppear {
            sessionStore.loadFromStorage()
        }
    }

    private var sessionAPIClient: CircleAPIClient {
        var client = apiClient
        client.tokenProvider = { [sessionStore] in sessionStore.token }
        return client
    }

    @ViewBuilder
    private func publishContent(imageData: Data) -> some View {
        switch destination {
        case .circle:
            CirclePostComposerView(
                initialImageData: imageData,
                allowsPhotoChange: false
            ) { data, title, tags in
                Task { await publishCircle(imageData: data, title: title, tags: tags) }
            }
        case .driftBottle:
            CircleDriftBottleThrowComposerView(
                initialImageData: imageData,
                allowsPhotoChange: false
            ) { data in
                Task { await publishDriftBottle(imageData: data) }
            }
        }
    }

    // MARK: - 上传逻辑（与 CircleView 同源；refresh 一次以容忍短期 401）

    @MainActor
    private func publishCircle(imageData: Data, title: String, tags: [String]) async {
        do {
            let token = try await validAccessToken()
            do {
                try await sessionAPIClient.createPost(imageData: imageData, title: title, tags: tags, accessToken: token)
            } catch CircleAPIError.unauthorized {
                let refreshed = try await validAccessToken(forceRefresh: true)
                try await sessionAPIClient.createPost(imageData: imageData, title: title, tags: tags, accessToken: refreshed)
            }
            onPublishSucceeded?(destination)
            dismiss()
        } catch {
            onPublishFailed?(error.localizedDescription)
        }
    }

    @MainActor
    private func publishDriftBottle(imageData: Data) async {
        do {
            let token = try await validAccessToken()
            do {
                try await sessionAPIClient.createDriftBottle(imageData: imageData, accessToken: token)
            } catch CircleAPIError.unauthorized {
                let refreshed = try await validAccessToken(forceRefresh: true)
                try await sessionAPIClient.createDriftBottle(imageData: imageData, accessToken: refreshed)
            }
            onPublishSucceeded?(destination)
            dismiss()
        } catch {
            onPublishFailed?(error.localizedDescription)
        }
    }

    @MainActor
    private func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let refreshToken = sessionStore.refreshToken else {
            throw CircleAPIError.missingAuthToken
        }
        if forceRefresh || sessionStore.shouldRefreshAccessToken {
            let session = try await apiClient.refreshSession(refreshToken: refreshToken)
            sessionStore.saveSession(session)
        }
        guard let token = sessionStore.token else {
            throw CircleAPIError.missingAuthToken
        }
        return token
    }

    private static func defaultAPIClient() -> CircleAPIClient {
        CircleAPIClient(
            baseURL: URL(string: "https://potato.xiaogousi.online")!,
            tokenProvider: {
                let token = UserDefaults.standard.string(forKey: "circleAccessToken") ?? ""
                return token.isEmpty ? nil : token
            }
        )
    }
}

// MARK: - Adjustment Step

// 400×600 canvas 上的可交互裁切；几何 / 手势与 InteractiveDevicePreview 同源，
// 但画布严格按 2:3 显示，且 baseDrawRect 计算的 targetSize 也是 400×600，
// 所以用户在屏幕上看到的 = jpegData 之后实际上传的内容。
struct GalleryShareAdjustmentView: View {
    let photo: GalleryPhoto
    let destination: GalleryShareDestination
    let onContinue: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var adjustment: EInkManualAdjustment
    @State private var gestureScaleStart: CGFloat = 1
    @State private var gestureRotationStart: CGFloat = 0
    @State private var gestureOffsetStart: CGSize = .zero
    @State private var isRendering = false

    init(
        photo: GalleryPhoto,
        destination: GalleryShareDestination,
        onContinue: @escaping (Data) -> Void
    ) {
        self.photo = photo
        self.destination = destination
        self.onContinue = onContinue
        // 用同一份 .gallery 调整作为初始值：用户在 TransferSheetView 里已经调过的图
        // 进入分享流程时不需要从头再调。
        let saved = TransferEditStateStore.load(for: .gallery(photo.id))
        _adjustment = State(initialValue: saved ?? .default)
    }

    private var targetSize: CGSize { GallerySharePreparer.shareCanvasSize }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 12)

                cropCanvas
                    .padding(.horizontal, 24)

                Spacer(minLength: 12)

                Form {
                    Section {
                        sliderRow(title: "缩放", value: $adjustment.scale, range: 0.25...3, format: scalePercent)
                        sliderRow(title: "旋转", value: $adjustment.rotation, range: -.pi...(.pi), format: rotationDegrees)
                        sliderRow(title: "水平", value: $adjustment.offsetX, range: -160...160, format: offsetText)
                        sliderRow(title: "垂直", value: $adjustment.offsetY, range: -160...160, format: offsetText)
                    } header: {
                        HStack {
                            Text("手动调整")
                            Spacer()
                            if adjustment != .default {
                                Button("重置") {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        adjustment = .default
                                    }
                                }
                                .font(.footnote)
                            }
                        }
                    } footer: {
                        Text("画框 = 400 × 600，是真正上传给服务端的尺寸。")
                            .font(.footnote)
                    }
                }
                .scrollDisabled(true)
                .frame(maxHeight: 320)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomActionBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text(destination.navigationTitle)
                        .font(.headline)
                }
            }
        }
    }

    // MARK: 400×600 canvas

    private var cropCanvas: some View {
        // 维持 2:3 (400:600 = 2:3) 比例，最大不超过屏幕的合理范围。
        GeometryReader { proxy in
            let maxWidth: CGFloat = min(proxy.size.width, 280)
            let maxHeight: CGFloat = min(proxy.size.height, maxWidth * (targetSize.height / targetSize.width))
            let width: CGFloat = min(maxWidth, maxHeight * (targetSize.width / targetSize.height))
            let height: CGFloat = width * (targetSize.height / targetSize.width)

            ZStack {
                cropScreen
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
                    .gesture(combinedGesture)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(targetSize.width / targetSize.height, contentMode: .fit)
    }

    private var cropScreen: some View {
        GeometryReader { proxy in
            // 与 InteractiveDevicePreview 完全同源的几何公式：
            //   baseScale = max(canvasW / imgW, canvasH / imgH)  → 居中铺满
            //   offsetScale 把存储的 offsetX/Y (单位: targetSize 像素) 映射到当前预览的 point。
            let baseScale = max(proxy.size.width / photo.image.size.width, proxy.size.height / photo.image.size.height)
            let offsetScale = min(proxy.size.width / targetSize.width, proxy.size.height / targetSize.height)

            Image(uiImage: photo.image)
                .resizable()
                .interpolation(.medium)
                .frame(width: photo.image.size.width * baseScale, height: photo.image.size.height * baseScale)
                .scaleEffect(adjustment.scale)
                .rotationEffect(.radians(Double(adjustment.rotation)))
                .offset(x: adjustment.offsetX * offsetScale, y: adjustment.offsetY * offsetScale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.white)
        .clipped()
        .contentShape(Rectangle())
    }

    private var combinedGesture: some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                adjustment.offsetX = clampOffset(gestureOffsetStart.width + value.translation.width)
                adjustment.offsetY = clampOffset(gestureOffsetStart.height + value.translation.height)
            }
            .onEnded { _ in
                gestureOffsetStart = CGSize(width: adjustment.offsetX, height: adjustment.offsetY)
            }

        let magnify = MagnificationGesture()
            .onChanged { value in
                adjustment.scale = clampScale(gestureScaleStart * value)
            }
            .onEnded { _ in
                gestureScaleStart = adjustment.scale
            }

        let rotate = RotationGesture()
            .onChanged { angle in
                adjustment.rotation = clampRotation(gestureRotationStart + CGFloat(angle.radians))
            }
            .onEnded { _ in
                gestureRotationStart = adjustment.rotation
            }

        return SimultaneousGesture(SimultaneousGesture(magnify, rotate), drag)
    }

    private func clampScale(_ value: CGFloat) -> CGFloat { min(max(value, 0.25), 3) }
    private func clampOffset(_ value: CGFloat) -> CGFloat { min(max(value, -160), 160) }
    private func clampRotation(_ value: CGFloat) -> CGFloat { min(max(value, -.pi), .pi) }

    // MARK: 底部 CTA

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                continueToPublish()
            } label: {
                HStack(spacing: 8) {
                    if isRendering {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text(destination.continueButtonTitle)
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isRendering)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }

    private func continueToPublish() {
        guard !isRendering else { return }
        isRendering = true
        // 切到后台线程做 renderer + jpeg 编码，避免在主线程卡顿。
        let currentImage = photo.image
        let currentAdjustment = adjustment
        Task.detached(priority: .userInitiated) {
            let data = GallerySharePreparer.renderShareImageData(
                for: currentImage,
                adjustment: currentAdjustment
            )
            await MainActor.run {
                isRendering = false
                guard let data else { return }
                onContinue(data)
            }
        }
    }

    // MARK: 滑块格式化

    private func sliderRow(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        format: @escaping (CGFloat) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(title) {
                Text(format(value.wrappedValue))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            Slider(value: value, in: range)
        }
    }

    private func scalePercent(_ value: CGFloat) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func rotationDegrees(_ value: CGFloat) -> String {
        let degrees = value * 180 / .pi
        return String(format: "%.0f°", degrees)
    }

    private func offsetText(_ value: CGFloat) -> String {
        "\(Int(value.rounded()))"
    }
}
