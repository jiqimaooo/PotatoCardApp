import SwiftUI
import UIKit

struct TodoView: View {
    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = TodoStore()
    @State private var newTodoTitle = ""
    @State private var editingItemID: UUID?
    @State private var editingTitle = ""
    @State private var pendingDisplayImage: UIImage?
    @FocusState private var focusedTodoID: UUID?
    @FocusState private var isNewTodoFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerView
            transferStatusView
            todoList
            addTodoView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: bleService.transferPhase) { _, phase in
            guard phase == .succeeded, let pendingDisplayImage else { return }
            bleService.markLastTransferredImage(pendingDisplayImage)
            self.pendingDisplayImage = nil
        }
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("todos")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryTextColor)

                Text("\(store.items.filter { !$0.isDone }.count) 项未完成")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                EditButton()
                    .font(.system(size: 14, weight: .semibold))

                Button {
                    syncTodos()
                } label: {
                    Label("同步到设备", systemImage: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(height: 34)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSync)
                .accessibilityLabel("同步到设备")
            }
        }
    }

    private var addTodoView: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accentColor)
                .frame(width: 22, height: 22)

            TextField("添加待办", text: $newTodoTitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(primaryTextColor)
                .submitLabel(.done)
                .focused($isNewTodoFocused)
                .onSubmit(addTodo)

            Button {
                addTodo()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(accentColor)
            .disabled(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("新增待办")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(inputFillColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var transferStatusView: some View {
        if activeDevice == nil {
            statusText("请先连接设备")
        } else if bleService.transferPhase == .preparing || bleService.transferPhase == .transferring {
            VStack(alignment: .leading, spacing: 7) {
                ProgressView(value: bleService.transferProgress)
                statusText("\(bleService.transferPhase.title) \(Int(bleService.transferProgress * 100))%")
            }
        } else if case .failed = bleService.transferPhase, let errorMessage = bleService.errorMessage {
            statusText(errorMessage, color: .red)
        }
    }

    private var todoList: some View {
        List {
            if store.items.isEmpty {
                emptyStateRow
            } else {
                ForEach(store.items) { item in
                    todoRow(for: item)
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
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 54)
    }

    private var emptyStateRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("暂无待办")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryTextColor)

            Text("添加第一项待办后，可以同步到墨水屏。")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func todoRow(for item: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                store.toggleDone(item)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(item.isDone ? accentColor : secondaryTextColor.opacity(0.55), lineWidth: 1.6)
                        .frame(width: 22, height: 22)

                    if item.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(accentColor)
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "取消完成" : "完成待办")

            if editingItemID == item.id {
                TextField("Todo", text: $editingTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(primaryTextColor)
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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(item.isDone ? secondaryTextColor : primaryTextColor)
                        .strikethrough(item.isDone, color: secondaryTextColor)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(rowFillColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
    }

    private func statusText(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color ?? secondaryTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        bleService.transfer(image: transferImage, to: device)
    }

    private var canSync: Bool {
        guard activeDevice != nil else { return false }
        return bleService.transferPhase != .preparing && bleService.transferPhase != .transferring
    }

    private var activeDevice: BleDevice? {
        bleService.connectedDevice ?? bleService.selectedDevice
    }

    private var accentColor: Color {
        Color(red: 0.18, green: 0.49, blue: 0.98)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.92)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.64) : Color.black.opacity(0.52)
    }

    private var inputFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.78)
    }

    private var rowFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.68)
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
    }
}

private struct TodoView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            TodoView()
                .environmentObject(BleTransferService(forcePreviewPrompt: true))
                .padding(.horizontal, 24)
                .padding(.top, 22)
        }
    }
}
