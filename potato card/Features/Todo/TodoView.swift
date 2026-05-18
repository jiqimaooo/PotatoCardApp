import SwiftUI
import UIKit

struct TodoView: View {
    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = TodoStore()
    @State private var newTodoTitle = ""
    @State private var isClearConfirmationPresented = false
    @State private var editingItemID: UUID?
    @State private var editingTitle = ""
    @State private var pendingDisplayImage: UIImage?
    @State private var checkboxFeedbackID: UUID?
    @FocusState private var focusedTodoID: UUID?
    @FocusState private var isNewTodoFocused: Bool

    var body: some View {
        ZStack {
            pageBackgroundColor
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                headerView
                syncSection
                todoList
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            addTodoView
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .background(pageBackgroundColor)
        }
        .background {
            KeyboardDismissTapLayer {
                dismissTodoKeyboard()
            }
            .frame(width: 0, height: 0)
        }
        .onChange(of: bleService.transferPhase) { phase in
            guard phase == .succeeded, let pendingDisplayImage else { return }
            bleService.markLastTransferredImage(pendingDisplayImage)
            self.pendingDisplayImage = nil
        }
        .alert("确认清空所有待办？", isPresented: $isClearConfirmationPresented) {
            Button("清空全部", role: .destructive) {
                store.clearAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可撤销。")
        }
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("待办")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(titleTextColor)

                Text("\(store.items.filter { !$0.isDone }.count) 项未完成")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(subtitleTextColor)
            }

            Spacer(minLength: 12)

            Button {
                isClearConfirmationPresented = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))

                    Text("一键清空")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(titleTextColor)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(headerActionFillColor, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(headerActionStrokeColor, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(store.items.isEmpty)
            .opacity(store.items.isEmpty ? 0.55 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                syncTodos()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: syncCardSymbolName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(syncCardTextColor)
                        .frame(width: 18, height: 18)

                    Text("同步到设备")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(syncCardTextColor)

                    Spacer(minLength: 12)

                    syncCardTrailingView
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(syncCardBackgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(canSync ? 1 : 0.92)
            .disabled(!canSync)

            if case .failed = bleService.transferPhase, let errorMessage = bleService.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.92))
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var syncCardTrailingView: some View {
        if bleService.transferPhase == .preparing || bleService.transferPhase == .transferring {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(syncCardTextColor)

                Text("\(Int(bleService.transferProgress * 100))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(syncCardTextColor)
                    .monospacedDigit()
            }
        } else if activeDevice == nil {
            Text("未连接")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(syncCardTextColor.opacity(0.78))
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(syncCardTextColor.opacity(0.72))
        }
    }

    private var todoList: some View {
        List {
            if store.items.isEmpty {
                emptyStateRow
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                    todoRow(for: item, isLast: index == store.items.count - 1)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
                .onDelete(perform: store.delete)
                .onMove(perform: store.move)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(
            listContainerColor,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(listContainerStrokeColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.05), radius: 20, x: 0, y: 8)
        .environment(\.defaultMinListRowHeight, 64)
    }

    private var emptyStateRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("暂无待办")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(titleTextColor)

            Text("添加第一项待办后，可以同步到墨水屏。")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(subtitleTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 26)
    }

    private func todoRow(for item: TodoItem, isLast: Bool) -> some View {
        HStack(spacing: 14) {
            checkboxButton(for: item)

            if editingItemID == item.id {
                TextField("待办", text: $editingTitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(todoTextColor)
                    .submitLabel(.done)
                    .focused($focusedTodoID, equals: item.id)
                    .onSubmit {
                        commitEditing(item)
                    }
                    .onDisappear {
                        commitEditing(item)
                    }
            } else {
                Button {
                    beginEditing(item)
                } label: {
                    Text(item.title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(item.isDone ? completedTodoTextColor : todoTextColor)
                        .strikethrough(item.isDone, color: completedTodoTextColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)
                    .padding(.leading, 58)
                    .padding(.trailing, 20)
            }
        }
    }

    private func checkboxButton(for item: TodoItem) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.62)) {
                checkboxFeedbackID = item.id
            }
            store.toggleDone(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                    if checkboxFeedbackID == item.id {
                        checkboxFeedbackID = nil
                    }
                }
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(item.isDone ? accentColor : checkboxBorderColor, lineWidth: 2)
                    .background(
                        Circle()
                            .fill(item.isDone ? accentColor : Color.clear)
                    )
                    .frame(width: 26, height: 26)

                if item.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(checkboxFeedbackID == item.id ? 0.88 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: checkboxFeedbackID == item.id)
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: item.isDone)
        .accessibilityLabel(item.isDone ? "取消完成" : "完成待办")
    }

    private var addTodoView: some View {
        HStack(spacing: 12) {
            TextField("", text: $newTodoTitle, prompt: Text("添加新待办…").foregroundColor(placeholderTextColor))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(todoTextColor)
                .submitLabel(.done)
                .focused($isNewTodoFocused)
                .onSubmit(addTodo)

            Button {
                addTodo()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? accentColor.opacity(0.35) : accentColor)
                    )
            }
            .buttonStyle(.plain)
            .disabled(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("新增待办")
        }
        .frame(height: 52)
        .padding(.horizontal, 16)
        .background(
            addTodoContainerColor,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(addTodoContainerStrokeColor, lineWidth: 1)
        )
        .shadow(color: addTodoShadowColor, radius: 18, x: 0, y: 8)
    }

    private func addTodo() {
        store.add(newTodoTitle)
        newTodoTitle = ""
        isNewTodoFocused = true
    }

    private func beginEditing(_ item: TodoItem) {
        editingItemID = item.id
        editingTitle = item.title
        DispatchQueue.main.async {
            focusedTodoID = item.id
        }
    }

    private func commitEditing(_ item: TodoItem) {
        guard editingItemID == item.id else { return }
        let trimmedTitle = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            store.update(item, title: trimmedTitle)
        }
        editingItemID = nil
        editingTitle = ""
        focusedTodoID = nil
    }

    private func dismissTodoKeyboard() {
        // 点空白区域时，如果正在编辑已有待办，先保存编辑内容再收起键盘。
        if let editingItemID, let item = store.items.first(where: { $0.id == editingItemID }) {
            commitEditing(item)
        }
        focusedTodoID = nil
        isNewTodoFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func syncTodos() {
        guard let device = activeDevice else { return }

        let displayImage = TodoEInkRenderer.renderDisplayImage(
            items: store.items,
            targetSize: device.profile.pixelSize
        )
        let transferImage = EInkImageRenderer.renderForTransfer(
            image: displayImage,
            targetSize: device.profile.pixelSize,
            fitMode: .centerCrop,
            profile: device.profile,
            ditherAlgorithm: bleService.ditherAlgorithm
        )

        pendingDisplayImage = displayImage
        bleService.transfer(image: transferImage, displayImage: displayImage, to: device)
    }

    private var canSync: Bool {
        guard activeDevice != nil else { return false }
        return bleService.transferPhase != .preparing && bleService.transferPhase != .transferring
    }

    private var activeDevice: BleDevice? {
        bleService.connectedDevice ?? bleService.selectedDevice
    }

    private var syncCardSymbolName: String {
        activeDevice == nil ? "paperplane" : "paperplane.fill"
    }

    private var accentColor: Color {
        Color(red: 0, green: 122 / 255, blue: 1)
    }

    private var pageBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.10)
            : Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    }

    private var titleTextColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.94)
            : Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    }

    private var subtitleTextColor: Color {
        Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    }

    private var syncCardBackgroundColor: Color {
        colorScheme == .dark
            ? accentColor.opacity(0.16)
            : Color(red: 238 / 255, green: 245 / 255, blue: 1)
    }

    private var syncCardTextColor: Color {
        accentColor
    }

    private var listContainerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : .white
    }

    private var listContainerStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255)
    }

    private var checkboxBorderColor: Color {
        Color(red: 199 / 255, green: 199 / 255, blue: 204 / 255)
    }

    private var todoTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    }

    private var completedTodoTextColor: Color {
        Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    }

    private var placeholderTextColor: Color {
        subtitleTextColor.opacity(0.88)
    }

    private var headerActionFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white
    }

    private var headerActionStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    private var addTodoContainerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : .white
    }

    private var addTodoContainerStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.03)
    }

    private var addTodoShadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.22 : 0.07)
    }
}

private struct KeyboardDismissTapLayer: UIViewRepresentable {
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> UIView {
        let view = KeyboardDismissHostView()
        view.backgroundColor = .clear
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void
        private weak var attachedWindow: UIWindow?
        private weak var recognizer: UITapGestureRecognizer?

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        deinit {
            if let recognizer {
                attachedWindow?.removeGestureRecognizer(recognizer)
            }
        }

        func attach(to window: UIWindow?) {
            if attachedWindow === window { return }

            if let recognizer {
                attachedWindow?.removeGestureRecognizer(recognizer)
            }

            guard let window else {
                attachedWindow = nil
                recognizer = nil
                return
            }

            // 挂到 window 上只监听点击，不盖在 SwiftUI 内容上，避免影响按钮和列表交互。
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            attachedWindow = window
            self.recognizer = recognizer
        }

        @objc func handleTap() {
            onTap()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // 点到输入控件本身时不处理，避免刚获得焦点又立刻收起键盘。
            guard let touchedView = touch.view else { return true }
            return !touchedView.isTextInputDescendant
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private final class KeyboardDismissHostView: UIView {
    var onWindowChange: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window)
    }
}

private extension UIView {
    var isTextInputDescendant: Bool {
        if self is UITextField || self is UITextView {
            return true
        }
        return superview?.isTextInputDescendant ?? false
    }
}

private struct TodoView_Previews: PreviewProvider {
    static var previews: some View {
        TodoView()
            .environmentObject(BleTransferService(forcePreviewPrompt: true))
    }
}
