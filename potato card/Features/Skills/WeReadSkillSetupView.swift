import Combine
import SafariServices
import SwiftUI
import UIKit

@MainActor
final class WeReadSkillSetupStore: ObservableObject {
    enum StatusTone {
        case neutral
        case success
        case warning
    }

    let tokenPageURL = URL(string: "https://weread.qq.com/r/weread-skills")!

    @Published var apiKeyInput = ""
    @Published var hasSavedKey = false
    @Published var isVerifying = false
    @Published var isKeyVisible = false
    @Published var statusText = "打开官方页面生成 Key，回到这里粘贴保存。"
    @Published var statusTone: StatusTone = .neutral
    @Published var toastMessage: String?

    init() {
        reloadSavedKey()
    }

    var savedKeyPreview: String {
        let value = apiKeyInput.trimmed
        guard !value.isEmpty else { return "等待填写" }
        guard value.count > 12 else { return value }
        let prefix = value.prefix(6)
        let suffix = value.suffix(4)
        return "\(prefix)••••\(suffix)"
    }

    func reloadSavedKey() {
        let savedValue = (try? WeReadAPIKeyStore.read())?.trimmed ?? ""
        hasSavedKey = !savedValue.isEmpty
        if !savedValue.isEmpty {
            apiKeyInput = savedValue
            statusText = "本机已保存微信读书 Key。"
            statusTone = .success
        } else if apiKeyInput.trimmed.isEmpty {
            statusText = "打开官方页面生成 Key，回到这里粘贴保存。"
            statusTone = .neutral
        }
    }

    func copyTokenPageLink() {
        UIPasteboard.general.string = tokenPageURL.absoluteString
        toastMessage = "领 Key 链接已复制"
    }

    func pasteAndSaveFromClipboard() {
        guard let rawValue = UIPasteboard.general.string?.trimmed, !rawValue.isEmpty else {
            statusText = "剪贴板里还没有微信读书 Key。"
            statusTone = .warning
            return
        }

        let token = extractToken(from: rawValue) ?? rawValue
        apiKeyInput = token
        saveCurrentKey()
    }

    func saveCurrentKey() {
        let value = apiKeyInput.trimmed
        guard !value.isEmpty else {
            statusText = "填写 Key 后即可保存。"
            statusTone = .warning
            return
        }

        guard value.hasPrefix("wrk-") else {
            statusText = "Key 格式需要以 wrk- 开头。"
            statusTone = .warning
            return
        }

        do {
            try WeReadAPIKeyStore.save(value)
            apiKeyInput = value
            hasSavedKey = true
            statusText = "Key 已保存到本机 Keychain。"
            statusTone = .success
            toastMessage = "保存完成"
        } catch {
            statusText = error.localizedDescription
            statusTone = .warning
        }
    }

    func clearSavedKey() {
        do {
            try WeReadAPIKeyStore.delete()
            apiKeyInput = ""
            hasSavedKey = false
            statusText = "本机 Key 已清空。"
            statusTone = .neutral
            toastMessage = "已清空"
        } catch {
            statusText = error.localizedDescription
            statusTone = .warning
        }
    }

    func verifyCurrentKey() async {
        let value = apiKeyInput.trimmed
        guard !value.isEmpty else {
            statusText = "填写 Key 后即可校验。"
            statusTone = .warning
            return
        }

        guard value.hasPrefix("wrk-") else {
            statusText = "Key 格式需要以 wrk- 开头。"
            statusTone = .warning
            return
        }

        saveCurrentKey()
        isVerifying = true
        statusText = "正在校验微信读书连接..."
        statusTone = .neutral

        defer {
            isVerifying = false
        }

        do {
            try await WeReadGatewayClient(apiKeyProvider: { value }).verifyKey()
            statusText = "校验通过，可以读取书架、笔记、书评、推荐和阅读统计。"
            statusTone = .success
            toastMessage = "微信读书已接入"
        } catch {
            statusText = error.localizedDescription
            statusTone = .warning
        }
    }

    private func extractToken(from rawValue: String) -> String? {
        let pattern = #"wrk-[A-Za-z0-9\-_]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(rawValue.startIndex..<rawValue.endIndex, in: rawValue)
        guard let match = regex.firstMatch(in: rawValue, options: [], range: range),
              let tokenRange = Range(match.range, in: rawValue) else {
            return nil
        }
        return String(rawValue[tokenRange])
    }
}

struct WeReadSkillSetupView: View {
    @StateObject private var store = WeReadSkillSetupStore()
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsTokenPage = false
    @State private var confirmsKeyDeletion = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                quickStartCard
                keySection
                capabilitySection
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, AppBottomBarMetrics.scrollContentBottomPadding)
        }
        .background(pageBackgroundColor.ignoresSafeArea())
        .dismissKeyboardOnBackgroundTap()
        .navigationTitle("微信读书")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsTokenPage) {
            WeReadTokenPageView(url: store.tokenPageURL)
                .ignoresSafeArea()
        }
        .alert("清空本机保存的微信读书 Key？", isPresented: $confirmsKeyDeletion) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                store.clearSavedKey()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .weReadAPIKeyDidChange)) { _ in
            store.reloadSavedKey()
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toastMessage {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .padding(.bottom, AppBottomBarMetrics.floatingControlBottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.2)) {
                                store.toastMessage = nil
                            }
                        }
                    }
            }
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.63, blue: 0.48),
                            Color(red: 0.18, green: 0.49, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text("微信读书")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryTextColor)
                Text("一键跳转官方领 Key 页面，回到 App 粘贴保存，客户端直接读取微信读书开放数据。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(cardStroke)
    }

    private var quickStartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("快速接入")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(primaryTextColor)

            VStack(alignment: .leading, spacing: 10) {
                quickStartRow(index: 1, title: "打开官方领 Key 页面", detail: "微信读书登录同一账号后生成 wrk- 开头的个人 Key。")
                quickStartRow(index: 2, title: "复制 Key 回到 App", detail: "支持整段文本粘贴，App 会自动提取 wrk- token。")
                quickStartRow(index: 3, title: "保存并校验连接", detail: "Key 会保存到本机 Keychain，校验通过后即可接技能。")
            }

            HStack(spacing: 10) {
                Button {
                    showsTokenPage = true
                } label: {
                    Label("打开领 Key 页面", systemImage: "link")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    store.copyTokenPageLink()
                } label: {
                    Label("复制链接", systemImage: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 118, height: 42)
                        .background(rowFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke)
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("个人 Key")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(primaryTextColor)
                    Text(store.hasSavedKey ? "当前已保存：\(store.savedKeyPreview)" : "当前状态：等待填写")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer()

                Button("清空") {
                    confirmsKeyDeletion = true
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                .disabled(!store.hasSavedKey && store.apiKeyInput.trimmed.isEmpty)
            }

            HStack(spacing: 8) {
                Group {
                    if store.isKeyVisible {
                        TextField("输入或粘贴 wrk- 开头的 Key", text: $store.apiKeyInput)
                    } else {
                        SecureField("输入或粘贴 wrk- 开头的 Key", text: $store.apiKeyInput)
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(primaryTextColor)

                Button {
                    store.isKeyVisible.toggle()
                } label: {
                    Image(systemName: store.isKeyVisible ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 46)
            .background(rowFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    store.pasteAndSaveFromClipboard()
                } label: {
                    Label("一键粘贴并保存", systemImage: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(rowFillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    store.saveCurrentKey()
                } label: {
                    Label("保存 Key", systemImage: "tray.and.arrow.down.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 118, height: 40)
                        .background(rowFillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                Task {
                    await store.verifyCurrentKey()
                }
            } label: {
                HStack(spacing: 8) {
                    if store.isVerifying {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    }
                    Text(store.isVerifying ? "校验中…" : "校验连接")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(store.isVerifying ? 0.8 : 1)
            }
            .buttonStyle(.plain)
            .disabled(store.isVerifying)

            statusBanner
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke)
    }

    private var statusBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusIconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(statusColor)
                .frame(width: 20, height: 20)

            Text(store.statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(primaryTextColor)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(statusColor.opacity(colorScheme == .dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var capabilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("接入后可读取")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(primaryTextColor)

            VStack(spacing: 10) {
                capabilityRow(icon: "books.vertical.fill", title: "书架", detail: "电子书、有声书、文章收藏入口、私密状态、最近阅读时间")
                capabilityRow(icon: "magnifyingglass", title: "搜索与详情", detail: "书名、作者、评分、简介、目录、阅读进度")
                capabilityRow(icon: "clock.arrow.circlepath", title: "阅读统计", detail: "周月年总时长、阅读天数、偏好分类、作者、出版社")
                capabilityRow(icon: "highlighter", title: "笔记与划线", detail: "有笔记的书、划线原文、个人想法、热门划线")
                capabilityRow(icon: "text.quote", title: "书评", detail: "推荐、最新、一般、差评等公开点评")
                capabilityRow(icon: "sparkles.rectangle.stack", title: "推荐", detail: "为你推荐、相似书推荐")
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke)
    }

    private func quickStartRow(index: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func capabilityRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(rowFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusIconName: String {
        switch store.statusTone {
        case .neutral:
            return "info.circle.fill"
        case .success:
            return "checkmark.seal.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch store.statusTone {
        case .neutral:
            return accentColor
        case .success:
            return Color(red: 0.10, green: 0.65, blue: 0.36)
        case .warning:
            return Color(red: 0.94, green: 0.52, blue: 0.17)
        }
    }

    private var pageBackgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(red: 0.98, green: 0.98, blue: 0.98)
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : .white
    }

    private var rowFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045)
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(cardStrokeColor, lineWidth: 1)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.52)
    }

    private var accentColor: Color {
        Color(red: 0.18, green: 0.49, blue: 0.98)
    }
}

private struct WeReadTokenPageView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(Color(red: 0.18, green: 0.49, blue: 0.98))
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
