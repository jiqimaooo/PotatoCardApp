import PhotosUI
import SwiftUI

struct CircleRegistrationView: View {
    @EnvironmentObject private var bleService: BleTransferService
    @ObservedObject var sessionStore: CircleSessionStore
    let apiClient: CircleAPIClient

    @StateObject private var passkeyService = CirclePasskeyService()
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var username = ""
    @State private var errorMessage: String?
    @State private var isRegistering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("加入圈子")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("先绑定你的土豆片，再创建通行密钥。圈子里只展示用户名和头像，不公开设备标识。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            deviceState

            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                Label(avatarData == nil ? "选择头像" : "已选择头像", systemImage: "person.crop.circle")
            }
            .buttonStyle(.bordered)
            .disabled(isRegistering)

            TextField("用户名", text: $username)
                .textFieldStyle(.roundedBorder)
                .disabled(isRegistering)

            Button(isRegistering ? "注册中" : "创建通行密钥并注册") {
                register()
            }
            .buttonStyle(.borderedProminent)
            .disabled(activeDevice == nil || avatarData == nil || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRegistering)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(24)
        .task(id: selectedAvatarItem) {
            avatarData = try? await selectedAvatarItem?.loadTransferable(type: Data.self)
        }
    }

    private var deviceState: some View {
        Group {
            if let activeDevice {
                Label(activeDevice.name, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("请先在设备页连接或选择土豆片", systemImage: "iphone.slash")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 15, weight: .semibold))
    }

    private var activeDevice: BleDevice? {
        bleService.connectedDevice ?? bleService.selectedDevice
    }

    private func register() {
        guard let activeDevice else { return }
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else { return }

        isRegistering = true
        errorMessage = nil
        Task {
            do {
                let options = try await apiClient.createRegisterOptions(
                    rawDeviceIdentifier: activeDevice.id,
                    username: trimmedUsername
                )
                let passkeyResponse = try await passkeyService.createRegistration(options: options)
                let session = try await apiClient.verifyRegistration(
                    rawDeviceIdentifier: activeDevice.id,
                    username: trimmedUsername,
                    avatarKey: "avatars/\(UUID().uuidString).jpg",
                    challenge: options.challenge,
                    response: passkeyResponse
                )
                sessionStore.saveSession(token: session.accessToken, profile: session.profile)
            } catch {
                errorMessage = error.localizedDescription
            }
            isRegistering = false
        }
    }
}
