//
//  GalleryShareFlow.swift
//  potato card
//
//  长按 / 从 viewer toolbar 菜单走到「分享到圈子 / 漂流瓶」的入口。
//
//  - GalleryShareDestination：区分两条分享链路。
//  - GallerySharePreparer：给一张图 + 一份 EInkManualAdjustment 渲染 400×600 JPEG。
//    与「传输到设备」走同一套 EInkImageRenderer.render 几何，保证【上传】
//    与【预览】【在黑灯火上看到的】表现一致。
//  - GalleryShareSheet：充当两段状态机——未登录先走注册 / 登录；
//    登录后直接跳到 composer，预填一张按用户已保存调整渲染出的 400×600 预览图，
//    只留一个「下一步 / 发布 / 发送」按钮。不再插入二次调整面板。
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
}

enum GallerySharePreparer {
    // 圈子 / 漂流瓶服务端约定的画布尺寸：与土豆片墨水屏 400×600 主屏一致。
    static let shareCanvasSize = CGSize(width: 400, height: 600)
    private static let shareJPEGCompressionQuality: CGFloat = 0.85

    // 按调用方传入的 EInkManualAdjustment 渲染 400×600 JPEG。
    // 与 EInkImageRenderer.render 完全同源，所以「预览画面」≡
    // 「上传给服务端的画面」≡「最终别人传到墨水屏的画面」。
    static func renderShareImageData(
        for image: UIImage,
        adjustment: EInkManualAdjustment
    ) -> Data? {
        // 默认调整 → 走 .centerCrop，避免给从未编辑的图引入空白边。
        let fitMode: EInkImageFitMode = adjustment == .default ? .centerCrop : .manual
        let rendered = EInkImageRenderer.render(
            image: image,
            targetSize: shareCanvasSize,
            fitMode: fitMode,
            adjustment: adjustment
        )
        return rendered.jpegData(compressionQuality: shareJPEGCompressionQuality)
    }

    // 默认入口：读当前照片在 TransferEditStateStore 里已保存的 .gallery 调整。
    static func preparedShareImageData(for photo: GalleryPhoto) -> Data? {
        let adjustment = TransferEditStateStore.load(for: .gallery(photo.id)) ?? .default
        return renderShareImageData(for: photo.image, adjustment: adjustment)
    }
}

// MARK: - Share Sheet Container

struct GalleryShareSheet: View {
    let destination: GalleryShareDestination
    let onPublishSucceeded: ((GalleryShareDestination) -> Void)?
    let onPublishFailed: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var sessionStore = CircleSessionStore()
    // 预渲染出的 400×600 JPEG 数据。.task 在页面第一次 ready 时填一次；
    // 后续登录成功后也会填一次。composer 拿这份数据作为预填图。
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
                // 未登录 → 先走注册 / 登录。登录成功后自动跳到 composer。
                CircleRegistrationView(sessionStore: sessionStore, apiClient: apiClient)
            } else {
                publishContent(imageData: preparedImageData)
            }
        }
        .onAppear {
            sessionStore.loadFromStorage()
            if preparedImageData == nil {
                preparedImageData = GallerySharePreparer.preparedShareImageData(for: destination.photo)
            }
        }
        .onChange(of: sessionStore.isRegistered) { isRegistered in
            // 刚登录完还没 onAppear 过的分支上创建出 composer：补一次预渲染。
            guard isRegistered, preparedImageData == nil else { return }
            preparedImageData = GallerySharePreparer.preparedShareImageData(for: destination.photo)
        }
    }

    private var sessionAPIClient: CircleAPIClient {
        var client = apiClient
        client.tokenProvider = { [sessionStore] in sessionStore.token }
        return client
    }

    @ViewBuilder
    private func publishContent(imageData: Data?) -> some View {
        // 预渲染未完成时给个占位 ProgressView，避免 composer 拿不到初始图。
        // 实际上 renderShareImageData 同步运行很快，onAppear 中就给填上了，
        // 这里只是干掉 nil 额外开销。
        if let imageData {
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
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
