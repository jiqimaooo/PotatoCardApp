import SwiftUI
import UIKit

struct MyView: View {
    let onShowDeviceDiagnostics: () -> Void

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
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
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
        guard !isRefreshingCircleProfile, let refreshToken = circleSessionStore.refreshToken else { return }
        isRefreshingCircleProfile = true
        defer { isRefreshingCircleProfile = false }

        let apiClient = CircleAPIClient(
            baseURL: URL(string: "https://potato.xiaogousi.online")!,
            tokenProvider: { circleSessionStore.token }
        )

        do {
            let session = try await apiClient.refreshSession(refreshToken: refreshToken)
            circleSessionStore.saveSession(session)
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

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.045, green: 0.045, blue: 0.05) : Color(red: 0.985, green: 0.985, blue: 0.975)
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
                    Text("本项目已开源，欢迎交流与贡献。")
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
        }
    }
}
