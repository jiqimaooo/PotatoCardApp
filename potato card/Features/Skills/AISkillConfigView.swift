import SwiftUI
import UIKit

struct AISkillConfigView: View {
    @StateObject private var store = AISkillSettingsStore()
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmsKeyDeletion = false
    @State private var confirmsAPITest = false
    @State private var isTestingAPI = false
    @State private var apiTestError: AIImageParsedError?
    @State private var showsDebugLogSheet = false
    @State private var isAPIKeyVisible = false
    @State private var customModelInput = ""
    @State private var showsCustomModelManager = false
    @State private var apiDebugLogs: [String] = []

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                providerSection
                keySection
                generationSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, AppBottomBarMetrics.scrollContentBottomPadding)
        }
        .background(pageBackgroundColor.ignoresSafeArea())
        .dismissKeyboardOnBackgroundTap()
        .navigationTitle("AI 生图")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.refreshAPIKeyState()
        }
        .alert("确定删除已保存的 API Key 吗？", isPresented: $confirmsKeyDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                store.clearAPIKey()
            }
        }
        .alert("确定测试吗？会消耗 API 额度", isPresented: $confirmsAPITest) {
            Button("取消", role: .cancel) {}
            Button("测试", role: .destructive) {
                testAPI()
            }
        }
        .sheet(isPresented: $showsDebugLogSheet) {
            AIImageDebugLogSheet(
                logs: apiDebugLogs,
                isTesting: isTestingAPI,
                onCopy: {
                    copyDetailedLog(apiDebugLogs.joined(separator: "\n"))
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsCustomModelManager) {
            AIModelManagementSheet(store: store)
                .presentationDetents([.medium, .large])
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
                            Color(red: 0.30, green: 0.48, blue: 1.00),
                            Color(red: 0.75, green: 0.34, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text("AI 生图")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryTextColor)
                Text("快捷指令输入 Prompt，生成适配土豆片的 400×600 图片。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(cardStroke)
    }

    private var providerSection: some View {
        VStack(spacing: 0) {
            PickerRow(title: "模型服务") {
                Picker("模型服务", selection: Binding(
                    get: { store.config.provider },
                    set: { provider in
                        store.updateProvider(provider)
                        customModelInput = ""
                        apiTestError = nil
                    }
                )) {
                    ForEach(AIImageModelProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .labelsHidden()
            }
            dividerRow
            modelPickerSection
            dividerRow
            customModelSection
        }
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke)
    }

    private var modelPickerSection: some View {
        PickerRow(title: "默认模型") {
            Picker("默认模型", selection: Binding(
                get: { store.config.defaultModel },
                set: { modelID in
                    store.selectModel(modelID)
                    apiTestError = nil
                }
            )) {
                ForEach(store.availableModelOptions) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .labelsHidden()
        }
    }

    private var customModelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("输入自定义模型 ID ", text: $customModelInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(rowFillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("确认") {
                    store.addCustomModel(customModelInput)
                    customModelInput = ""
                    apiTestError = nil
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)
                .disabled(customModelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Button {
                showsCustomModelManager = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                    Text(store.customModels.isEmpty ? "管理自定义模型" : "管理自定义模型 · \(store.customModels.count)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(secondaryTextColor)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("API Key")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(primaryTextColor)

                        Button {
                            showsDebugLogSheet = true
                        } label: {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(secondaryTextColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看 AI 生图调试日志")
                    }
                    Text(store.keyStatusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(store.apiKeyExists ? .green : secondaryTextColor)
                }

                Spacer()

                Button("清空 Key") {
                    confirmsKeyDeletion = true
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                .disabled(!store.apiKeyExists && store.apiKeyInput.isEmpty)
            }

            apiKeyInputField

            Button {
                confirmsAPITest = true
            } label: {
                HStack(spacing: 8) {
                    if isTestingAPI {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    }
                    Text(isTestingAPI ? "测试中…" : "测试 API")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(isTestingAPI ? 0.78 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isTestingAPI)

            if let apiTestError {
                errorCard(error: apiTestError)
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke)
    }

    private var apiKeyInputField: some View {
        let apiKeyBinding = Binding<String>(
            get: { store.apiKeyInput },
            set: { value in
                store.updateAPIKey(value)
                apiTestError = nil
            }
        )

        return HStack(spacing: 8) {
            Group {
                // 小眼睛只切换展示方式，不改变 Keychain 保存逻辑。
                if isAPIKeyVisible {
                    TextField("请输入当前模型服务的 API Key", text: apiKeyBinding)
                } else {
                    SecureField("请输入当前模型服务的 API Key", text: apiKeyBinding)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 14, weight: .medium))

            Button {
                isAPIKeyVisible.toggle()
            } label: {
                Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAPIKeyVisible ? "隐藏 API Key" : "显示 API Key")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 44)
        .background(rowFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func errorCard(error: AIImageParsedError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.18))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(error.message)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                    Text(error.suggestion)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            Button {
                copyDetailedLog(error.rawLog)
            } label: {
                Label("复制详细日志", systemImage: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(rowFillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(primaryTextColor)
        }
        .padding(12)
        .background(Color(red: 1.0, green: 0.58, blue: 0.16).opacity(colorScheme == .dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 1.0, green: 0.58, blue: 0.16).opacity(0.24), lineWidth: 1)
        )
    }

    private var generationSection: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("默认尺寸")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                    Spacer()
                    Picker("默认尺寸", selection: Binding(
                        get: { store.config.defaultSize },
                        set: { size in
                            store.updateDefaultSize(size)
                            apiTestError = nil
                        }
                    )) {
                        ForEach(AIImageSize.supportedDefaults, id: \.displayText) { size in
                            Text(size.displayText).tag(size)
                        }
                    }
                    .labelsHidden()
                }

                Text("此处为模型返回图片后的裁剪尺寸，若快捷指令中已设置，则以快捷指令配置为准。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 74)

            dividerRow

            VStack(alignment: .leading, spacing: 8) {
                Text("固定生成要求")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                TextEditor(text: Binding(
                    get: { store.config.promptTemplate },
                    set: { store.updatePromptTemplate($0) }
                ))
                .font(.system(size: 14, weight: .medium))
                .frame(minHeight: 92)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(rowFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("快捷指令输入的文案会自动拼接在这段要求后面。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }
            .padding(16)

            dividerRow

            toggleRow(title: "生成后直接传输到设备", isOn: Binding(
                get: { store.config.autoTransferToDevice },
                set: { store.updateAutoTransferToDevice($0) }
            ))
        }
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke)
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(primaryTextColor)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .tint(accentColor)
    }

    private var dividerRow: some View {
        Rectangle()
            .fill(cardStrokeColor)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func testAPI() {
        guard !isTestingAPI else { return }
        apiTestError = nil
        apiDebugLogs.removeAll()
        appendDebugLog("开始测试 API")
        appendDebugLog("提示：点击标题旁叹号可实时查看完整测试日志")
        isTestingAPI = true
        Task {
            defer {
                Task { @MainActor in
                    appendDebugLog("测试流程结束")
                    isTestingAPI = false
                }
            }

            do {
                try await AIImageGenerationService().testAPI(debugLog: appendDebugLog)
                await MainActor.run {
                    store.toastMessage = "API 可用"
                }
            } catch {
                let parsed = AIImageErrorParser.parse(error, provider: store.config.provider)
                await MainActor.run {
                    appendDebugLog("可读错误：\(parsed.message)")
                    appendDebugLog("建议操作：\(parsed.suggestion)")
                    apiTestError = parsed
                }
            }
        }
    }

    @MainActor
    private func appendDebugLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        apiDebugLogs.append("[\(formatter.string(from: Date()))] \(message)")
    }

    private func copyDetailedLog(_ rawLog: String) {
        UIPasteboard.general.string = rawLog
        store.toastMessage = "错误日志已复制"
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

private struct AIModelManagementSheet: View {
    @ObservedObject var store: AISkillSettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingDeletionModel: String?
    @State private var showsDeleteConfirmation = false
    @State private var showsClearAllConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    customModelList
                }
                .padding(20)
            }
            .background(pageBackgroundColor.ignoresSafeArea())
            .navigationTitle("自定义模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("确定删除这个自定义模型吗？", isPresented: $showsDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let pendingDeletionModel {
                        store.deleteCustomModel(pendingDeletionModel)
                    }
                    pendingDeletionModel = nil
                }
            }
            .alert("确定清空全部自定义模型吗？", isPresented: $showsClearAllConfirmation) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    store.clearCustomModels()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.config.provider.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(primaryTextColor)
            Text("这里只管理当前模型服务下手动添加的模型，内置模型不会被删除。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(cardStroke)
    }

    private var customModelList: some View {
        VStack(spacing: 0) {
            if store.customModels.isEmpty {
                Text("暂无自定义模型")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                ForEach(Array(store.customModels.enumerated()), id: \.element) { index, modelID in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(modelID)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(primaryTextColor)
                                .lineLimit(1)
                            if store.config.defaultModel == modelID {
                                Text("当前选中")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color(red: 0.18, green: 0.49, blue: 0.98))
                            }
                        }

                        Spacer()

                        Button {
                            pendingDeletionModel = modelID
                            showsDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除自定义模型")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 58)

                    if index < store.customModels.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }

                Divider()
                    .padding(.leading, 16)

                Button {
                    showsClearAllConfirmation = true
                } label: {
                    Text("清空全部自定义模型")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
            }
        }
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(cardStroke)
    }

    private var pageBackgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(red: 0.98, green: 0.98, blue: 0.98)
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : .white
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055), lineWidth: 1)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.52)
    }
}

private struct PickerRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.88))
            Spacer()
            content
                .foregroundStyle(Color.black.opacity(0.88))
                .tint(Color.black.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 220, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }
}

private struct AIImageDebugLogSheet: View {
    let logs: [String]
    let isTesting: Bool
    let onCopy: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isTesting ? Color.green : Color.secondary.opacity(0.55))
                        .frame(width: 8, height: 8)
                    Text(isTesting ? "测试运行中" : "最近一次测试日志")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if logs.isEmpty {
                                Text("还没有测试日志。点击「测试 API」后，这里会实时打印请求进度。")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(secondaryTextColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                            } else {
                                ForEach(Array(logs.enumerated()), id: \.offset) { index, log in
                                    Text(log)
                                        .id(index)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(primaryTextColor)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(14)
                    }
                    .background(logFillColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onChange(of: logs.count) { _ in
                        guard let last = logs.indices.last else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }

                Button {
                    onCopy()
                } label: {
                    Label("复制日志", systemImage: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(buttonFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(primaryTextColor)
                .disabled(logs.isEmpty)
                .opacity(logs.isEmpty ? 0.45 : 1)
            }
            .padding(18)
            .background(pageBackgroundColor.ignoresSafeArea())
            .navigationTitle("AI 生图日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var pageBackgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(red: 0.98, green: 0.98, blue: 0.98)
    }

    private var logFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045)
    }

    private var buttonFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.86)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.52)
    }
}
