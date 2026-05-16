import PhotosUI
import SwiftUI
import UIKit
import WebKit

struct CircleRegistrationView: View {
    @EnvironmentObject private var bleService: BleTransferService
    @ObservedObject var sessionStore: CircleSessionStore
    let apiClient: CircleAPIClient

    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isRegistering = false
    @State private var selectedLegalDocument: CircleLegalDocument?
    @State private var authMode: CirclePasswordAuthMode = .register
    @FocusState private var usernameFocused: Bool
    @FocusState private var passwordFocused: Bool

    private let circleGreen = Color(red: 0.23, green: 0.68, blue: 0.28)
    private let softGreen = Color(red: 0.91, green: 0.97, blue: 0.91)
    private let ink = Color(red: 0.06, green: 0.07, blue: 0.08)
    private let hairline = Color.black.opacity(0.08)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                if authMode == .register {
                    stepperSection
                }
                formSection
                passwordExplainer
                actionSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Color.white.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .task(id: selectedAvatarItem) {
            avatarData = try? await selectedAvatarItem?.loadTransferable(type: Data.self)
        }
        .sheet(item: $selectedLegalDocument) { document in
            CircleLegalWebView(document: document, url: legalURL(for: document))
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text("加入圈子")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.82)
                    .accessibilityAddTraits(.isHeader)

                Text(authMode == .register ? "先绑定你的土豆片，再设置临时登录密码。圈子里只展示用户名和头像，不公开设备标识。" : "使用用户名和密码登录圈子。后续开通开发者能力后会切回通行密钥。")
                    .font(.system(size: 14, weight: .semibold))
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 82)
            .frame(maxWidth: .infinity, alignment: .leading)

            CirclePotatoHeroIllustration()
                .frame(width: 78, height: 78)
                .opacity(0.86)
                .offset(x: 8, y: -4)
                .accessibilityHidden(true)
        }
        .padding(.bottom, 32)
    }

    private var stepperSection: some View {
        HStack(spacing: 0) {
            CircleRegistrationStep(number: 1, title: "绑定设备", isCompleted: activeDevice != nil, isActive: false)

            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 6)

            CircleRegistrationStep(number: 2, title: "创建密钥", isCompleted: false, isActive: true)

            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 6)

            CircleRegistrationStep(number: 3, title: "加入圈子", isCompleted: false, isActive: false)
        }
        .padding(.vertical, 2)
        .padding(.bottom, 30)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("注册进度，当前第 2 步，创建密钥")
    }

    private var formSection: some View {
        VStack(spacing: 0) {
            if authMode == .register {
                deviceCard

                Divider()
                    .overlay(Color.black.opacity(0.06))
                    .padding(.leading, 64)

                avatarPicker

                Divider()
                    .overlay(Color.black.opacity(0.06))
                    .padding(.leading, 64)
            }

            usernameField

            Divider()
                .overlay(Color.black.opacity(0.06))
                .padding(.leading, 64)

            passwordField
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(hairline, lineWidth: 1)
        }
    }

    private var deviceCard: some View {
        HStack(spacing: 12) {
            Image(systemName: activeDevice == nil ? "iphone.slash" : "checkmark.circle.fill")
                .font(.system(size: activeDevice == nil ? 22 : 32, weight: .semibold))
                .foregroundStyle(activeDevice == nil ? .secondary : circleGreen)
                .frame(width: 48, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text(activeDevice == nil ? "请先连接设备" : "设备已连接")
                    .font(.system(size: activeDevice == nil ? 14 : 17, weight: .bold))
                    .foregroundStyle(activeDevice == nil ? .secondary : ink)

                Text(activeDevice?.name ?? "前往设备页连接土豆片硬件")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            if let activeDevice {
                Button {
                    UIPasteboard.general.string = activeDevice.id
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(circleGreen)
                        .labelStyle(.titleAndIcon)
                        .frame(minWidth: 56, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制设备标识")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(minHeight: 78)
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
            HStack(spacing: 12) {
                avatarPreview

                VStack(alignment: .leading, spacing: 3) {
                    Text("头像")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(ink)

                    Text(avatarData == nil ? "选择一个圈子头像" : "已选择，可重新选择")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.28))
                    .frame(width: 20, height: 44)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 78)
        }
        .buttonStyle(.plain)
        .disabled(isRegistering)
        .accessibilityLabel(avatarData == nil ? "选择圈子头像" : "重新选择圈子头像")
    }

    private var avatarPreview: some View {
        ZStack {
            Circle()
                .fill(avatarData == nil ? softGreen : Color.white)
                .frame(width: 46, height: 46)

            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(circleGreen)
            }
        }
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Image(systemName: "person")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(usernameFocused ? circleGreen : .secondary)
                    .frame(width: 48, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text("用户名")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(ink)

                    TextField("请输入用户名，2-20 个字符", text: $username)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ink)
                        .focused($usernameFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .disabled(isRegistering)
                        .onChange(of: username) { newValue in
                            if newValue.count > 20 {
                                username = String(newValue.prefix(20))
                            }
                        }
                }

                Text("\(username.count)/20")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isUsernameValid || username.isEmpty ? .secondary : Color.red)
                    .monospacedDigit()
            }
            .frame(minHeight: 78)
            .padding(.horizontal, 18)

            if !username.isEmpty && !isUsernameValid {
                Label("用户名需要 2-20 个字符", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .accessibilityLabel("用户名需要 2 到 20 个字符")
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(usernameFocused ? circleGreen : .clear)
                .frame(width: 3)
                .padding(.vertical, 12)
        }
    }

    private var passwordField: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(passwordFocused ? circleGreen : .secondary)
                .frame(width: 48, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("密码")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ink)

                SecureField("请输入密码，至少 6 个字符", text: $password)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ink)
                    .focused($passwordFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .disabled(isRegistering)
                    .onChange(of: password) { newValue in
                        if newValue.count > 64 {
                            password = String(newValue.prefix(64))
                        }
                    }
            }
        }
        .frame(minHeight: 78)
        .padding(.horizontal, 18)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(passwordFocused ? circleGreen : .clear)
                .frame(width: 3)
                .padding(.vertical, 12)
        }
    }

    private var passwordExplainer: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.black.opacity(0.06))

            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 34)

                Text("当前临时使用密码，后续会切回通行密钥")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .padding(.top, 30)
    }

    private var actionSection: some View {
        VStack(spacing: 10) {
            Button {
                submit()
            } label: {
                HStack(spacing: 10) {
                    if isRegistering {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: authMode == .register ? "person.badge.plus" : "person.crop.circle.badge.checkmark")
                            .font(.system(size: 18, weight: .bold))
                    }

                    Text(actionTitle)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background {
                    Capsule()
                        .fill(registrationDisabled ? Color.gray.opacity(0.36) : circleGreen)
                        .shadow(color: registrationDisabled ? .clear : circleGreen.opacity(0.16), radius: 8, x: 0, y: 5)
                }
            }
            .buttonStyle(CirclePrimaryButtonStyle())
            .disabled(registrationDisabled)
            .accessibilityHint(registrationDisabledReason)

            Button {
                switchAuthMode()
            } label: {
                Text(authMode == .register ? "已有账号？登录" : "没有账号？创建圈子身份")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(circleGreen)
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.plain)
            .disabled(isRegistering)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            HStack(alignment: .center, spacing: 7) {
                Image(systemName: "shield")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                termsLine
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.top, 44)
    }

    private var termsLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                termsPrefix
                termsButtons
            }

            VStack(spacing: 2) {
                termsPrefix
                termsButtons
            }
            .frame(maxWidth: .infinity)
        }
        .font(.system(size: 12, weight: .medium))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var termsPrefix: some View {
        Text("创建即表示你同意遵守圈子的")
            .foregroundStyle(.secondary)
    }

    private var termsButtons: some View {
        HStack(spacing: 0) {
            Button {
                selectedLegalDocument = .terms
            } label: {
                Text("使用规范")
                    .foregroundStyle(circleGreen)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看使用规范")

            Text("和")
                .foregroundStyle(.secondary)

            Button {
                selectedLegalDocument = .privacy
            } label: {
                Text("隐私政策")
                    .foregroundStyle(circleGreen)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看隐私政策")
        }
    }

    private var activeDevice: BleDevice? {
        bleService.connectedDevice
    }

    private var avatarImage: UIImage? {
        guard let avatarData else { return nil }
        return UIImage(data: avatarData)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isUsernameValid: Bool {
        (2...20).contains(trimmedUsername.count)
    }

    private var isPasswordValid: Bool {
        (6...64).contains(password.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }

    private var registrationDisabled: Bool {
        switch authMode {
        case .register:
            return activeDevice == nil || avatarData == nil || !isUsernameValid || !isPasswordValid || isRegistering
        case .login:
            return !isUsernameValid || !isPasswordValid || isRegistering
        }
    }

    private var registrationDisabledReason: String {
        if authMode == .register && activeDevice == nil { return "请先连接土豆片硬件" }
        if authMode == .register && avatarData == nil { return "请先选择头像" }
        if !isUsernameValid { return "请输入 2 到 20 个字符的用户名" }
        if !isPasswordValid { return "请输入至少 6 个字符的密码" }
        return isRegistering ? "正在处理" : ""
    }

    private var actionTitle: String {
        if isRegistering {
            return authMode == .register ? "正在注册" : "正在登录"
        }
        return authMode == .register ? "注册并加入圈子" : "登录圈子"
    }

    private func legalURL(for document: CircleLegalDocument) -> URL {
        apiClient.baseURL.appendingPathComponent(document.path)
    }

    private func submit() {
        switch authMode {
        case .register:
            registerWithPassword()
        case .login:
            loginWithPassword()
        }
    }

    private func registerWithPassword() {
        guard let activeDevice, isUsernameValid, isPasswordValid, avatarData != nil else { return }

        isRegistering = true
        errorMessage = nil
        usernameFocused = false
        passwordFocused = false
        Task {
            do {
                let session = try await apiClient.registerWithPassword(
                    rawDeviceIdentifier: activeDevice.id,
                    username: trimmedUsername,
                    password: password.trimmingCharacters(in: .whitespacesAndNewlines),
                    avatarKey: "avatars/\(UUID().uuidString).jpg"
                )
                sessionStore.saveSession(token: session.accessToken, profile: session.profile)
            } catch {
                errorMessage = error.localizedDescription
            }
            isRegistering = false
        }
    }

    private func loginWithPassword() {
        guard isUsernameValid, isPasswordValid else { return }

        isRegistering = true
        errorMessage = nil
        usernameFocused = false
        passwordFocused = false
        Task {
            do {
                let session = try await apiClient.loginWithPassword(
                    username: trimmedUsername,
                    password: password.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                sessionStore.saveSession(token: session.accessToken, profile: session.profile)
            } catch {
                errorMessage = error.localizedDescription
            }
            isRegistering = false
        }
    }

    private func switchAuthMode() {
        errorMessage = nil
        usernameFocused = false
        passwordFocused = false
        authMode = authMode == .register ? .login : .register
    }
}

private enum CircleLegalDocument: Identifiable {
    case terms
    case privacy

    var id: String {
        path
    }

    var title: String {
        switch self {
        case .terms:
            return "使用规范"
        case .privacy:
            return "隐私政策"
        }
    }

    var path: String {
        switch self {
        case .terms:
            return "legal/terms"
        case .privacy:
            return "legal/privacy"
        }
    }
}

private enum CirclePasswordAuthMode {
    case register
    case login
}

private struct CircleLegalWebView: View {
    @Environment(\.dismiss) private var dismiss

    let document: CircleLegalDocument
    let url: URL

    var body: some View {
        NavigationStack {
            CircleWebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct CircleWebView: UIViewRepresentable {
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

private struct CirclePotatoHeroIllustration: View {
    private let green = Color(red: 0.23, green: 0.68, blue: 0.28)

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color(red: 0.90, green: 0.96, blue: 0.90))
                .frame(width: 74, height: 64)
                .rotationEffect(.degrees(-18))
                .offset(x: 3, y: 4)

            Circle()
                .fill(green.opacity(0.18))
                .frame(width: 10, height: 10)
                .offset(x: -32, y: -25)

            Circle()
                .fill(green.opacity(0.16))
                .frame(width: 9, height: 9)
                .offset(x: 34, y: 30)

            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.97, green: 0.83, blue: 0.52), Color(red: 0.89, green: 0.68, blue: 0.34)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 41, height: 54)
                .rotationEffect(.degrees(5))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 5)

            HStack(spacing: 11) {
                Circle().fill(Color.black.opacity(0.72)).frame(width: 4, height: 4)
                Circle().fill(Color.black.opacity(0.72)).frame(width: 4, height: 4)
            }
            .offset(x: -3, y: -3)

            Capsule()
                .stroke(Color.black.opacity(0.62), lineWidth: 2)
                .frame(width: 10, height: 5)
                .mask(Rectangle().offset(y: 4))
                .offset(x: -3, y: 6)

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(green)
                .symbolRenderingMode(.hierarchical)
                .offset(x: 23, y: 18)
                .shadow(color: green.opacity(0.16), radius: 5, x: 0, y: 3)
        }
    }
}

private struct CircleRegistrationStep: View {
    let number: Int
    let title: String
    let isCompleted: Bool
    let isActive: Bool

    private let green = Color(red: 0.23, green: 0.68, blue: 0.28)

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(isCompleted ? green : .white)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Circle()
                            .stroke(stepStrokeColor, lineWidth: isActive ? 1.5 : 1)
                    }

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(isActive ? green : .secondary)
                }
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive || isCompleted ? Color(red: 0.06, green: 0.07, blue: 0.08) : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private var stepStrokeColor: Color {
        if isCompleted { return green }
        if isActive { return green }
        return Color.black.opacity(0.18)
    }
}

private struct CirclePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
