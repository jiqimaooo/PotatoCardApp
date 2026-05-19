//
//  GalleryShareFlow.swift
//  potato card
//
//  长按相册照片 → 分享到圈子 / 分享到漂流瓶 的容器视图与图片准备工具。
//
//  - GallerySharePreparer: 把任意 GalleryPhoto 按用户保存过的「手动调整」渲染成
//    400×600 的 JPEG，作为圈子 / 漂流瓶上传的统一素材。
//  - GalleryShareDestination: 区分两条分享链路。
//  - GalleryShareSheet: 入口容器；未登录时先弹出 CircleRegistrationView，
//    注册 / 登录成功后自动切到对应的发布界面。
//
//  注：复用 Circle 模块已有的 CirclePostComposerView /
//  CircleDriftBottleThrowComposerView，本文件只负责调度与登录拦截。
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
}

enum GallerySharePreparer {
    // 圈子 / 漂流瓶服务端约定的画布尺寸：与土豆片墨水屏 400×600 主屏一致，
    // 这样发布作品时其他用户拉到的图直接就能走「传输到设备」管线，无需再二次裁切。
    static let shareCanvasSize = CGSize(width: 400, height: 600)
    private static let shareJPEGCompressionQuality: CGFloat = 0.85

    static func preparedShareImageData(for photo: GalleryPhoto) -> Data? {
        let adjustment = TransferEditStateStore.load(for: .gallery(photo.id)) ?? .default
        // 跟 GalleryView.startTransfer 一致：只有真正保存过非默认调整才走 .manual，
        // 默认情况仍然按 .centerCrop 居中裁切，避免给从未编辑过的图引入空白边。
        let fitMode: EInkImageFitMode = adjustment == .default ? .centerCrop : .manual
        let rendered = EInkImageRenderer.render(
            image: photo.image,
            targetSize: shareCanvasSize,
            fitMode: fitMode,
            adjustment: adjustment
        )
        return rendered.jpegData(compressionQuality: shareJPEGCompressionQuality) ?? photo.imageData
    }
}

// MARK: - Share Sheet Container

struct GalleryShareSheet: View {
    let destination: GalleryShareDestination
    let onPublishSucceeded: ((GalleryShareDestination) -> Void)?
    let onPublishFailed: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var sessionStore = CircleSessionStore()
    @State private var status: PublishStatus = .idle
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

    private enum PublishStatus {
        case idle
        case uploading
        case succeeded
        case failed(String)
    }

    var body: some View {
        Group {
            if sessionStore.isRegistered {
                publishContent
            } else {
                // 未登录：先走 Circle 自己的注册 / 登录视图，
                // 登录成功后 isRegistered 切到 true，外层 Group 自动换到 publishContent。
                CircleRegistrationView(sessionStore: sessionStore, apiClient: apiClient)
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
    private var publishContent: some View {
        switch destination {
        case .circle(let photo):
            CirclePostComposerView(
                initialImageData: GallerySharePreparer.preparedShareImageData(for: photo),
                allowsPhotoChange: false
            ) { imageData, title, tags in
                Task { await publishCircle(imageData: imageData, title: title, tags: tags) }
            }
        case .driftBottle(let photo):
            CircleDriftBottleThrowComposerView(
                initialImageData: GallerySharePreparer.preparedShareImageData(for: photo),
                allowsPhotoChange: false
            ) { imageData in
                Task { await publishDriftBottle(imageData: imageData) }
            }
        }
    }

    // MARK: - 上传逻辑（最小化复刻 CircleView，避免把整套相册模块依赖到 Circle 内部）

    @MainActor
    private func publishCircle(imageData: Data, title: String, tags: [String]) async {
        status = .uploading
        do {
            let token = try await validAccessToken()
            do {
                try await sessionAPIClient.createPost(imageData: imageData, title: title, tags: tags, accessToken: token)
            } catch CircleAPIError.unauthorized {
                let refreshed = try await validAccessToken(forceRefresh: true)
                try await sessionAPIClient.createPost(imageData: imageData, title: title, tags: tags, accessToken: refreshed)
            }
            status = .succeeded
            onPublishSucceeded?(destination)
            dismiss()
        } catch {
            let message = error.localizedDescription
            status = .failed(message)
            onPublishFailed?(message)
        }
    }

    @MainActor
    private func publishDriftBottle(imageData: Data) async {
        status = .uploading
        do {
            let token = try await validAccessToken()
            do {
                try await sessionAPIClient.createDriftBottle(imageData: imageData, accessToken: token)
            } catch CircleAPIError.unauthorized {
                let refreshed = try await validAccessToken(forceRefresh: true)
                try await sessionAPIClient.createDriftBottle(imageData: imageData, accessToken: refreshed)
            }
            status = .succeeded
            onPublishSucceeded?(destination)
            dismiss()
        } catch {
            let message = error.localizedDescription
            status = .failed(message)
            onPublishFailed?(message)
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
