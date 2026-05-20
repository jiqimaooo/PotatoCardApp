import SwiftUI
import PhotosUI
import UIKit
import WebKit

struct MyView: View {
    let onShowDeviceDiagnostics: () -> Void

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var circleSessionStore = CircleSessionStore()
    @State private var usage = AppStorageUsage(currentCacheBytes: 0, clearableCacheBytes: 0)
    @State private var isLoadingStorage = false
    @State private var isRefreshingCircleProfile = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profileHeader

                ProductSettingsSection(title: "设备管理") {
                    Button {
                        onShowDeviceDiagnostics()
                    } label: {
                        ProductSettingsRow(
                            title: "设备诊断与日志",
                            subtitle: "设备状态、后台快捷指令、实时日志",
                            systemImage: "dot.radiowaves.left.and.right"
                        )
                    }
                    .buttonStyle(.plain)
                }

                ProductSettingsSection(title: "通用设置") {
                    NavigationLink {
                        CardPushShortcutSettingsView()
                    } label: {
                        ProductSettingsRow(
                            title: "快捷指令设置",
                            subtitle: "队列同步、图库存储",
                            systemImage: "wand.and.rays"
                        )
                    }
                    .buttonStyle(.plain)

                    ProductDivider()

                    NavigationLink {
                        GlobalImageAlgorithmView()
                    } label: {
                        ProductSettingsRow(
                            title: "图像算法",
                            subtitle: bleService.ditherAlgorithm.title,
                            systemImage: "circle.hexagongrid"
                        )
                    }
                    .buttonStyle(.plain)

                    ProductDivider()

                    NavigationLink {
                        StorageSettingsView(usage: $usage, onReloadUsage: reloadStorageUsage)
                    } label: {
                        ProductSettingsRow(
                            title: "存储空间",
                            subtitle: AppStorageManager.formattedSize(usage.currentCacheBytes),
                            systemImage: "internaldrive"
                        )
                    }
                    .buttonStyle(.plain)
                }

                ProductSettingsSection(title: "关于") {
                    VStack(spacing: 0) {
                        NavigationLink {
                            DeveloperInfoView()
                        } label: {
                            ProductSettingsRow(
                                title: "开发者信息",
                                subtitle: "王野 · @王野sp",
                                systemImage: "person.crop.circle"
                            )
                        }
                        .buttonStyle(.plain)

                        ProductDivider()

                        NavigationLink {
                            OpenSourceAcknowledgementsView()
                        } label: {
                            ProductSettingsRow(
                                title: "开源与致谢",
                                subtitle: "GitHub · Contributors",
                                systemImage: "curlybraces"
                            )
                        }
                        .buttonStyle(.plain)

                        ProductDivider()

                        NavigationLink {
                            AppInfoView()
                        } label: {
                            ProductSettingsRow(
                                title: "应用信息",
                                subtitle: "\(appName) · \(appVersion)",
                                systemImage: "app.badge"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .background(backgroundColor)
        .task {
            await loadCircleProfile()
            await reloadStorageUsage()
        }
        .refreshable {
            await loadCircleProfile()
            await reloadStorageUsage()
        }
        .onReceive(NotificationCenter.default.publisher(for: CircleSessionStore.didSignOutNotification)) { _ in
            Task {
                await loadCircleProfile()
            }
        }
    }

    private var profileHeader: some View {
        Group {
            if circleSessionStore.profile != nil {
                NavigationLink {
                    CircleSettingsView(sessionStore: circleSessionStore, apiClient: circleAPIClient)
                } label: {
                    profileHeaderContent
                }
                .buttonStyle(.plain)
            } else {
                profileHeaderContent
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private var profileHeaderContent: some View {
        HStack(spacing: 13) {
            headerAvatar

            VStack(alignment: .leading, spacing: 4) {
                Text(circleSessionStore.profile?.username ?? "PotatoCard")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(ProductTextTone.primary)

                Text("土豆片 · 六色墨水屏")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(ProductTextTone.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var headerAvatar: some View {
        if let profile = circleSessionStore.profile {
            CircleAvatarView(
                username: profile.username,
                avatarKey: profile.avatarKey,
                avatarUrl: profile.avatarUrl,
                size: 52,
                isImageLoadingEnabled: true
            )
        } else {
            BrandMarkView(size: 52)
        }
    }

    @MainActor
    private func loadCircleProfile() async {
        circleSessionStore.loadFromStorage()
        guard let profile = circleSessionStore.profile else { return }

        if profile.avatarUrl == nil,
           let cachedPosts = CircleFeedPostCache.shared.loadPosts(for: profile.id),
           let avatarUrl = cachedPosts.first(where: { $0.author.id == profile.id })?.author.avatarUrl {
            circleSessionStore.updateProfileAvatarURL(avatarUrl)
        }

        await refreshCircleProfile()
    }

    @MainActor
    private func refreshCircleProfile() async {
        guard !isRefreshingCircleProfile, circleSessionStore.refreshToken != nil else { return }
        isRefreshingCircleProfile = true
        defer { isRefreshingCircleProfile = false }

        do {
            _ = try await circleSessionStore.validAccessToken(using: circleAPIClient, forceRefresh: true)
        } catch {
            // 我的页头像刷新失败时保留本地缓存和占位图，不打断设置页面使用。
        }
    }

    @MainActor
    private func reloadStorageUsage() async {
        guard !isLoadingStorage else { return }
        isLoadingStorage = true
        let usage = await Task.detached(priority: .utility) {
            AppStorageManager.loadUsage()
        }.value
        self.usage = usage
        isLoadingStorage = false
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Potato Card"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var circleAPIClient: CircleAPIClient {
        CircleAPIClient(
            baseURL: URL(string: "https://potato.xiaogousi.online")!,
            tokenProvider: { circleSessionStore.token }
        )
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.045, green: 0.045, blue: 0.05) : Color(red: 0.985, green: 0.985, blue: 0.975)
    }
}

private struct CircleSettingsView: View {
    @ObservedObject var sessionStore: CircleSessionStore
    let apiClient: CircleAPIClient

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isUpdatingAvatar = false
    @State private var isPasswordSheetPresented = false
    @State private var showsSignOutConfirmation = false
    @State private var statusMessage: CircleSettingsStatusMessage?
    @State private var statusDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    ProductSettingsSection(title: "资料") {
                        VStack(spacing: 0) {
                            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                                CircleSettingsRow(
                                    title: "头像",
                                    subtitle: isUpdatingAvatar ? "正在上传新头像" : "点击更换圈子头像",
                                    systemImage: "person.crop.circle",
                                    showsChevron: true,
                                    isLoading: isUpdatingAvatar
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isUpdatingAvatar)

                            ProductDivider()

                            CircleSettingsInfoRow(
                                title: "用户名",
                                value: sessionStore.profile?.username ?? "-",
                                subtitle: "暂不支持修改",
                                systemImage: "person.text.rectangle"
                            )

                            ProductDivider()

                            CircleSettingsInfoRow(
                                title: "圈子身份",
                                value: sessionStore.isRegistered ? "已登录" : "未登录",
                                subtitle: "用于发布、领取和传输圈子内容",
                                systemImage: "checkmark.seal"
                            )
                        }
                    }

                    ProductSettingsSection(title: "账号安全") {
                        VStack(spacing: 0) {
                            Button {
                                isPasswordSheetPresented = true
                            } label: {
                                CircleSettingsRow(
                                    title: "修改密码",
                                    subtitle: "更新圈子登录密码",
                                    systemImage: "lock.rotation",
                                    showsChevron: true
                                )
                            }
                            .buttonStyle(.plain)

                            ProductDivider()

                            Button(role: .destructive) {
                                showsSignOutConfirmation = true
                            } label: {
                                CircleSettingsRow(
                                    title: "退出登录",
                                    subtitle: "退出当前圈子账号",
                                    systemImage: "rectangle.portrait.and.arrow.right",
                                    tint: .red,
                                    isDestructive: true,
                                    showsChevron: false
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ProductSettingsSection(title: "规则与隐私") {
                        VStack(spacing: 0) {
                            NavigationLink {
                                CircleSettingsLegalWebView(
                                    title: "使用规范",
                                    url: apiClient.baseURL.appendingPathComponent("legal/terms")
                                )
                            } label: {
                                CircleSettingsRow(
                                    title: "使用规范",
                                    subtitle: "社区内容与设备身份规则",
                                    systemImage: "doc.text",
                                    showsChevron: true
                                )
                            }
                            .buttonStyle(.plain)

                            ProductDivider()

                            NavigationLink {
                                CircleSettingsLegalWebView(
                                    title: "隐私政策",
                                    url: apiClient.baseURL.appendingPathComponent("legal/privacy")
                                )
                            } label: {
                                CircleSettingsRow(
                                    title: "隐私政策",
                                    subtitle: "了解数据收集与使用方式",
                                    systemImage: "hand.raised",
                                    showsChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, statusMessage == nil ? 32 : 86)
            }
            .scrollIndicators(.hidden)

            if let statusMessage {
                CircleSettingsStatusBanner(message: statusMessage)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(backgroundColor)
        .navigationTitle("圈子设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            sessionStore.loadFromStorage()
            if !sessionStore.isRegistered {
                dismiss()
            }
        }
        .onChange(of: selectedAvatarItem) { item in
            guard let item else { return }
            Task {
                await updateAvatar(with: item)
                selectedAvatarItem = nil
            }
        }
        .sheet(isPresented: $isPasswordSheetPresented) {
            CirclePasswordChangeView(sessionStore: sessionStore, apiClient: apiClient) { text, style in
                showStatus(text, style: style)
            }
        }
        .confirmationDialog(
            "确定退出圈子账号吗？",
            isPresented: $showsSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("退出登录", role: .destructive) {
                sessionStore.signOut()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后需要重新登录才能发布、领取或管理圈子内容。")
        }
    }

    @ViewBuilder
    private var header: some View {
        if let profile = sessionStore.profile {
            VStack(spacing: 12) {
                CircleAvatarView(
                    username: profile.username,
                    avatarKey: profile.avatarKey,
                    avatarUrl: profile.avatarUrl,
                    size: 96,
                    isImageLoadingEnabled: true
                )
                .overlay(alignment: .bottomTrailing) {
                    ZStack {
                        Circle()
                            .fill(backgroundColor)
                            .frame(width: 32, height: 32)

                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ProductTextTone.primary)
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .offset(x: 3, y: 3)
                }

                Text(profile.username)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(ProductTextTone.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    @MainActor
    private func updateAvatar(with item: PhotosPickerItem) async {
        guard !isUpdatingAvatar else { return }
        isUpdatingAvatar = true
        defer { isUpdatingAvatar = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                showStatus("无法读取所选图片", style: .error)
                return
            }
            let uploadData = avatarUploadData(from: data)
            let accessToken = try await sessionStore.validAccessToken(using: apiClient)
            let avatarKey = try await apiClient.uploadAvatar(imageData: uploadData)
            let profile = try await apiClient.updateProfileAvatar(avatarKey: avatarKey, accessToken: accessToken)
            sessionStore.updateProfile(profile)
            showStatus("头像已更新", style: .success)
        } catch {
            showStatus(error.localizedDescription, style: .error)
        }
    }

    private func avatarUploadData(from data: Data) -> Data {
        guard let image = UIImage(data: data), let compressed = image.jpegData(compressionQuality: 0.82) else {
            return data
        }
        return compressed
    }

    private func showStatus(_ text: String, style: CircleSettingsStatusMessage.Style) {
        statusDismissTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            statusMessage = CircleSettingsStatusMessage(text: text, style: style)
        }

        statusDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) {
                    statusMessage = nil
                }
            }
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.045, green: 0.045, blue: 0.05) : Color(red: 0.985, green: 0.985, blue: 0.975)
    }
}

private struct CirclePasswordChangeView: View {
    @ObservedObject var sessionStore: CircleSessionStore
    let apiClient: CircleAPIClient
    let onComplete: (String, CircleSettingsStatusMessage.Style) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ProductSettingsSection(title: "修改密码") {
                        VStack(spacing: 0) {
                            passwordField("当前密码", text: $currentPassword)
                            ProductDivider()
                            passwordField("新密码", text: $newPassword)
                            ProductDivider()
                            passwordField("确认新密码", text: $confirmPassword)
                        }
                    }

                    if let localError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(localError)
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isSaving ? "正在保存" : "保存新密码")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(saveButtonDisabled ? Color.gray.opacity(0.34) : Color(red: 0.83, green: 0.20, blue: 0.24), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(saveButtonDisabled)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(backgroundColor)
            .navigationTitle("修改密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func passwordField(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ProductTextTone.primary)
                .frame(width: 86, alignment: .leading)

            SecureField("请输入", text: text)
                .font(.system(size: 15, weight: .regular))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @MainActor
    private func submit() async {
        guard !isSaving else { return }
        guard newPassword == confirmPassword else {
            localError = "两次输入的新密码不一致"
            return
        }
        guard (6...64).contains(newPassword.count) else {
            localError = "新密码需要 6-64 个字符"
            return
        }

        isSaving = true
        localError = nil
        defer { isSaving = false }

        do {
            let accessToken = try await sessionStore.validAccessToken(using: apiClient)
            try await apiClient.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword,
                accessToken: accessToken
            )
            dismiss()
            onComplete("密码已更新", .success)
        } catch {
            localError = error.localizedDescription
        }
    }

    private var saveButtonDisabled: Bool {
        isSaving
            || currentPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || newPassword.isEmpty
            || confirmPassword.isEmpty
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.045, green: 0.045, blue: 0.05) : Color(red: 0.985, green: 0.985, blue: 0.975)
    }
}

private struct CircleSettingsRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = ProductTextTone.icon
    var isDestructive: Bool = false
    var showsChevron: Bool
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isDestructive ? .red : ProductTextTone.primary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ProductTextTone.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isLoading {
                ProgressView()
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ProductTextTone.chevron)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct CircleSettingsInfoRow: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(ProductTextTone.icon)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ProductTextTone.primary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ProductTextTone.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ProductTextTone.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct CircleSettingsStatusMessage: Identifiable, Equatable {
    enum Style {
        case success
        case error
    }

    let id = UUID()
    let text: String
    let style: Style
}

private struct CircleSettingsStatusBanner: View {
    let message: CircleSettingsStatusMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: message.style == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(message.style == .success ? .green : .red)

            Text(message.text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ProductTextTone.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
    }
}

private struct CircleSettingsLegalWebView: View {
    let title: String
    let url: URL

    var body: some View {
        CircleSettingsWebView(url: url)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}

private struct CircleSettingsWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.backgroundColor = .systemBackground
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}

private struct AppInfoView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            ProductSettingsSection(title: "应用信息") {
                VStack(spacing: 0) {
                    InfoValueRow(title: "App 名称", value: appName)
                    ProductDivider()
                    InfoValueRow(title: "当前版本号", value: appVersion)
                    ProductDivider()
                    InfoValueRow(title: "Build 号", value: buildNumber)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(backgroundColor)
        .navigationTitle("应用信息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.045, green: 0.045, blue: 0.05) : Color(red: 0.985, green: 0.985, blue: 0.975)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Potato Card"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }
}

private struct GlobalImageAlgorithmView: View {
    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProductSettingsSection(title: "全局图像算法") {
                    VStack(spacing: 0) {
                        ForEach(Array(EInkDitherAlgorithm.allCases.enumerated()), id: \.element.id) { index, algorithm in
                            Button {
                                bleService.setDitherAlgorithm(algorithm)
                            } label: {
                                algorithmRow(algorithm)
                            }
                            .buttonStyle(.plain)

                            if index != EInkDitherAlgorithm.allCases.count - 1 {
                                ProductDivider()
                            }
                        }
                    }
                }

                Text("全局算法会影响图库、专辑、待办、圈子等默认传图。手动编辑页选择具体算法后，只覆盖当前图片。")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(ProductTextTone.secondary)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(backgroundColor)
        .navigationTitle("图像算法")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func algorithmRow(_ algorithm: EInkDitherAlgorithm) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(ProductTextTone.icon)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(algorithm.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ProductTextTone.primary)

                Text(algorithm.subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ProductTextTone.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if bleService.ditherAlgorithm == algorithm {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.045, green: 0.045, blue: 0.05) : Color(red: 0.985, green: 0.985, blue: 0.975)
    }
}

private struct DeveloperInfoView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    private let authorGitHubURL = URL(string: "https://github.com/jiqimaooo")!

    var body: some View {
        ScrollView {
            ProductSettingsSection(title: "开发者信息") {
                VStack(spacing: 0) {
                    InfoValueRow(title: "作者", value: "王野")
                    ProductDivider()
                    Button {
                        open(URL(string: "https://weibo.com/u/1774818625")!)
                    } label: {
                        avatarExternalRow(
                            title: "@王野sp",
                            subtitle: "微博",
                            avatar: .asset("weibo_avatar")
                        )
                    }
                    .buttonStyle(.plain)

                    ProductDivider()

                    Button {
                        open(authorGitHubURL)
                    } label: {
                        avatarExternalRow(
                            title: "GitHub",
                            subtitle: "github.com/jiqimaooo",
                            avatar: .remote(URL(string: "https://github.com/jiqimaooo.png")!)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(backgroundColor)
        .navigationTitle("开发者信息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func avatarExternalRow(title: String, subtitle: String?, avatar: AboutAvatarSource) -> some View {
        AvatarExternalRow(title: title, subtitle: subtitle, avatar: avatar)
    }

    private func open(_ url: URL) {
        openURL(url)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.045, green: 0.045, blue: 0.05) : Color(red: 0.985, green: 0.985, blue: 0.975)
    }
}

private struct OpenSourceAcknowledgementsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    private let authorAvatarURL = URL(string: "https://github.com/jiqimaooo.png")!

    private let contributors = [
        Contributor(
            username: "Sunbelife",
            profileURL: URL(string: "https://github.com/Sunbelife")!,
            avatarURL: URL(string: "https://github.com/Sunbelife.png")!
        ),
        Contributor(
            username: "zzy0302",
            profileURL: URL(string: "https://github.com/zzy0302")!,
            avatarURL: URL(string: "https://github.com/zzy0302.png")!
        )
    ]

    var body: some View {
        ScrollView {
            ProductSettingsSection(title: "开源与致谢") {
                VStack(spacing: 0) {
                    Text("本项目前端已开源，欢迎交流与贡献。")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(ProductTextTone.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)

                    ProductDivider()

                    Button {
                        open(URL(string: "https://github.com/jiqimaooo/PotatoCardApp")!)
                    } label: {
                        avatarExternalRow(
                            title: "PotatoCardApp",
                            subtitle: "GitHub 仓库",
                            avatar: .remote(authorAvatarURL)
                        )
                    }
                    .buttonStyle(.plain)

                    ProductDivider()

                    Text("感谢以下贡献者对 PotatoCardApp 的支持与贡献。")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(ProductTextTone.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)

                    ProductDivider()

                    ForEach(Array(contributors.enumerated()), id: \.element.id) { index, contributor in
                        Button {
                            open(contributor.profileURL)
                        } label: {
                            contributorRow(contributor)
                        }
                        .buttonStyle(.plain)

                        if index != contributors.count - 1 {
                            ProductDivider()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(backgroundColor)
        .navigationTitle("开源与致谢")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func avatarExternalRow(title: String, subtitle: String?, avatar: AboutAvatarSource) -> some View {
        AvatarExternalRow(title: title, subtitle: subtitle, avatar: avatar)
    }

    private func contributorRow(_ contributor: Contributor) -> some View {
        HStack(spacing: 11) {
            AboutAvatarView(source: .remote(contributor.avatarURL), size: 32)

            Text(contributor.username)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ProductTextTone.primary)

            Spacer(minLength: 10)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ProductTextTone.chevron)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func open(_ url: URL) {
        openURL(url)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.045, green: 0.045, blue: 0.05) : Color(red: 0.985, green: 0.985, blue: 0.975)
    }
}

private struct BrandMarkView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)

            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)

            Image("ink_tatoo2")
                .resizable()
                .scaledToFit()
                .padding(size * 0.18)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 5)
    }
}

private enum ProductTextTone {
    static let primary = Color(uiColor: .label).opacity(0.94)
    static let secondary = Color(uiColor: .label).opacity(0.62)
    static let sectionTitle = Color(uiColor: .label).opacity(0.70)
    static let chevron = Color(uiColor: .label).opacity(0.34)
    static let icon = Color(uiColor: .label).opacity(0.58)
}

private struct ProductSettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ProductTextTone.sectionTitle)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content
            }
            .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 1)
            }
        }
    }
}

private struct ProductSettingsRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(ProductTextTone.icon)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ProductTextTone.primary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ProductTextTone.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ProductTextTone.chevron)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct InfoValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(ProductTextTone.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ProductTextTone.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct ProductDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1 / UIScreen.main.scale)
            .padding(.leading, 14)
    }
}

private enum AboutAvatarSource {
    case asset(String)
    case remote(URL)
}

private struct AvatarExternalRow: View {
    let title: String
    let subtitle: String?
    let avatar: AboutAvatarSource

    var body: some View {
        HStack(spacing: 11) {
            AboutAvatarView(source: avatar, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ProductTextTone.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(ProductTextTone.secondary)
                }
            }

            Spacer(minLength: 10)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ProductTextTone.chevron)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

private struct AboutAvatarView: View {
    let source: AboutAvatarSource
    let size: CGFloat

    var body: some View {
        Group {
            switch source {
            case .asset(let name):
                Image(name)
                    .resizable()
                    .scaledToFill()
            case .remote(let url):
                CachedRemoteAvatarView(url: url)
            }
        }
        .frame(width: size, height: size)
        .background(Color.secondary.opacity(0.10), in: Circle())
        .clipShape(Circle())
    }
}

private struct CachedRemoteAvatarView: View {
    let url: URL

    @State private var cachedImage: UIImage?

    var body: some View {
        Group {
            if let cachedImage {
                Image(uiImage: cachedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(3)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)

        // GitHub 头像使用 URLCache 做本地缓存，避免每次进入页面都重新拉取远程图片。
        if let cachedResponse = URLCache.shared.cachedResponse(for: request),
           let image = UIImage(data: cachedResponse.data) {
            cachedImage = image
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let image = UIImage(data: data) else { return }
            URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
            cachedImage = image
        } catch {
            // 头像加载失败时保留占位图，不影响页面主体内容。
        }
    }
}

private struct Contributor: Identifiable {
    var id: String { username }
    let username: String
    let profileURL: URL
    let avatarURL: URL
}

private struct StorageSettingsView: View {
    @Binding var usage: AppStorageUsage
    let onReloadUsage: () async -> Void

    @State private var isClearingCache = false
    @State private var showsClearCacheConfirmation = false
    @State private var alert: MyPageAlert?

    var body: some View {
        List {
            Section {
                storageMetricRow(title: "当前缓存占用", value: AppStorageManager.formattedSize(usage.currentCacheBytes))
                storageMetricRow(title: "可清理缓存", value: AppStorageManager.formattedSize(usage.clearableCacheBytes))
            } footer: {
                Text("不会删除图库、配置、账号信息、设备信息和待推送任务。")
            }

            Section {
                Button(role: .destructive) {
                    showsClearCacheConfirmation = true
                } label: {
                    HStack {
                        if isClearingCache {
                            ProgressView()
                        }
                        Text(isClearingCache ? "正在清理..." : "清理缓存")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(isClearingCache || usage.clearableCacheBytes == 0)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("存储空间")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            await onReloadUsage()
        }
        .confirmationDialog(
            "确定清理可清理缓存吗？",
            isPresented: $showsClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("清理缓存", role: .destructive) {
                Task { await clearCache() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("图库、配置、账号和设备信息会被保留。")
        }
        .alert(item: $alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
    }

    private func storageMetricRow(title: String, value: String) -> some View {
        LabeledContent {
            Text(value)
                .monospacedDigit()
        } label: {
            Text(title)
        }
    }

    @MainActor
    private func clearCache() async {
        guard !isClearingCache else { return }
        isClearingCache = true

        await Task.detached(priority: .utility) {
            AppStorageManager.clearCache()
        }.value
        await onReloadUsage()

        isClearingCache = false
        alert = MyPageAlert(title: "清理完成", message: "可清理缓存已清除。")
    }
}

private struct MyPageAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct MyView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MyView {}
                .environmentObject(BleTransferService.shared)
        }
    }
}
