import SwiftUI

struct CircleRegistrationView: View {
    @EnvironmentObject private var bleService: BleTransferService
    @ObservedObject var sessionStore: CircleSessionStore
    @State private var username = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("加入圈子")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("先绑定你的土豆片，再创建通行密钥。圈子里只展示用户名和头像，不公开设备标识。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            deviceState

            TextField("用户名", text: $username)
                .textFieldStyle(.roundedBorder)

            Button("创建通行密钥并注册") {
                register()
            }
            .buttonStyle(.borderedProminent)
            .disabled(activeDevice == nil || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(24)
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
        errorMessage = "请先连接圈子服务器后再注册"
    }
}
