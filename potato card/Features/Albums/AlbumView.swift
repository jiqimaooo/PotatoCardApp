//
//  AlbumView.swift
//  potato card
//

import SwiftUI
import UIKit

enum AlbumCatalog {
    static let jayAlbums: [String] = [
        "范特西",
        "八度空間",
        "葉惠美",
        "七里香",
        "11月的蕭邦",
        "依然范特西",
        "我很忙",
        "魔杰座",
        "跨時代",
        "驚嘆號",
        "十二新作",
        "周杰倫的床邊故事",
        "最伟大的作品"
    ]

    static let stefanieAlbums: [String] = [
        "孙燕姿",
        "我要的幸福",
        "风筝",
        "Start自选集",
        "The Moment",
        "完美的一天",
        "逆光",
        "跳舞的梵谷",
        "是时候",
        "克卜勒",
        "彩虹金刚",
        "未完成",
        "Leave"
    ]

    static var allAlbums: [String] {
        jayAlbums + stefanieAlbums
    }

    static var featuredAlbums: [String] {
        ["范特西", "七里香", "孙燕姿"]
    }
}

struct AlbumView: View {
    let onTransferToDevice: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedAlbum: SelectedAlbumGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("专辑")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(primaryTextColor)

            artistSection(title: "周杰伦", albums: AlbumCatalog.jayAlbums)
            artistSection(title: "孙燕姿", albums: AlbumCatalog.stefanieAlbums)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $selectedAlbum) { group in
            AlbumImageViewer(
                albums: group.albums,
                initialIndex: group.initialIndex,
                onTransferToDevice: onTransferToDevice
            )
                .presentationDetents([.height(560)])
                .presentationDragIndicator(.visible)
        }
    }

    private func artistSection(title: String, albums: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryTextColor)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Array(albums.enumerated()), id: \.element) { index, album in
                        albumCard(album, albums: albums, index: index)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.horizontal, -24)
        }
    }

    private func albumCard(_ album: String, albums: [String], index: Int) -> some View {
        Button {
            selectedAlbum = SelectedAlbumGroup(albums: albums, initialIndex: index)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(album)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )

                Text(album)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(2)
            }
            .frame(width: 148, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.92)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
}

private struct SelectedAlbumGroup: Identifiable {
    let id: String
    let albums: [String]
    let initialIndex: Int

    init(albums: [String], initialIndex: Int) {
        self.albums = albums
        self.initialIndex = initialIndex
        self.id = "\(albums.joined(separator: "|"))-\(initialIndex)"
    }
}

private struct AlbumImageViewer: View {
    let albums: [String]
    let initialIndex: Int
    let onTransferToDevice: (String) -> Void
    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndex: Int
    @State private var transferRequest: AlbumTransferRequest?
    @State private var pendingTransferAlbum: String?
    @State private var pendingTransferImage: UIImage?

    init(albums: [String], initialIndex: Int, onTransferToDevice: @escaping (String) -> Void) {
        self.albums = albums
        self.initialIndex = initialIndex
        self.onTransferToDevice = onTransferToDevice
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        let buttonFillColor = colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
        let secondaryTextColor = colorScheme == .dark ? Color.white.opacity(0.82) : Color.black.opacity(0.72)

        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()

                albumFramedPreview

                VStack {
                    Spacer()

                    VStack(spacing: 10) {
                        transferStatusView

                        // 主操作：使用 TransferProgressButton。空闲时为强调色胶囊按钮；
                        // 传输/等待时按钮自身复用为苹果风格的进度条，避免 disabled 状态下
                        // 背景色被系统抹平的问题。
                        TransferProgressButton(
                            idleTitle: "传输到设备",
                            inProgressTitle: "传输中",
                            progress: bleService.transferProgress,
                            isInProgress: isTransferInProgress,
                            isEnabled: activeDevice != nil,
                            action: transferSelectedAlbumDirectly,
                            height: 38,
                            fontSize: 14,
                            tint: Color(red: 0.0, green: 0.48, blue: 1.0)
                        )
                        .frame(minWidth: 160)

                        Button(action: openManualAdjustment) {
                            Text("手动调整")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(buttonFillColor.opacity(0.72))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isTransferInProgress)
                    }
                    .padding(.bottom, 10)
                    .offset(y: 20)
                }
            }
            .sheet(item: $transferRequest) { request in
                TransferSheetView(
                    sourceImage: request.image,
                    title: request.album,
                    editStateKey: .album(request.album),
                    onTransferSucceeded: {
                        onTransferToDevice(request.album)
                        dismiss()
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: bleService.transferPhase) { _, phase in
                guard phase == .succeeded, let album = pendingTransferAlbum else { return }
                if let pendingTransferImage {
                    bleService.markLastTransferredImage(pendingTransferImage)
                }
                onTransferToDevice(album)
                pendingTransferAlbum = nil
                pendingTransferImage = nil
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text(albums[selectedIndex])
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var transferStatusView: some View {
        // 进度展示已经合并到 TransferProgressButton 自身，这里只在失败时显示错误描述。
        if case .failed = bleService.transferPhase, let errorMessage = bleService.errorMessage {
            Text(errorMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private func transferSelectedAlbumDirectly() {
        guard
            let device = activeDevice,
            let image = UIImage(named: albums[selectedIndex])
        else {
            return
        }

        let transferImage = defaultTransferImage(from: image, device: device)
        let displayImage = defaultDisplayImage(from: image, device: device)
        pendingTransferAlbum = albums[selectedIndex]
        pendingTransferImage = displayImage
        bleService.transfer(image: transferImage, displayImage: displayImage, to: device)
    }

    private func openManualAdjustment() {
        let album = albums[selectedIndex]
        guard let image = UIImage(named: album) else { return }
        pendingTransferAlbum = nil
        pendingTransferImage = nil
        transferRequest = AlbumTransferRequest(album: album, image: image)
    }

    private func defaultTransferImage(from image: UIImage, device: BleDevice) -> UIImage {
        EInkImageRenderer.renderForTransfer(
            image: image,
            targetSize: device.profile.pixelSize,
            fitMode: .centerCrop,
            adjustment: .default,
            profile: device.profile,
            ditherAlgorithm: bleService.ditherAlgorithm
        )
    }

    private func defaultDisplayImage(from image: UIImage, device: BleDevice) -> UIImage {
        EInkImageRenderer.render(
            image: image,
            targetSize: device.profile.pixelSize,
            fitMode: .centerCrop,
            adjustment: .default
        )
    }

    private var activeDevice: BleDevice? {
        bleService.connectedDevice ?? bleService.selectedDevice
    }

    private var isTransferInProgress: Bool {
        bleService.transferPhase == .preparing || bleService.transferPhase == .transferring
    }

    private var albumFramedPreview: some View {
        ZStack {
            TabView(selection: $selectedIndex) {
                ForEach(Array(albums.enumerated()), id: \.offset) { index, album in
                    albumScreenImage(album)
                        .tag(index)
                }
            }
            .frame(width: 186, height: 280)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .mask(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .frame(width: 186, height: 280)
            )
            .offset(y: -19)

            Image("ink_tatoo2")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220)
                .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
                .allowsHitTesting(false)
        }
        .frame(width: 220, height: 352)
        .offset(y: -60)
    }

    private func albumScreenImage(_ album: String) -> some View {
        return GeometryReader { proxy in
            Image(album)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .frame(width: 186, height: 280)
    }

}

private struct AlbumTransferRequest: Identifiable {
    let id = UUID()
    let album: String
    let image: UIImage
}

private struct AlbumView_Previews: PreviewProvider {
    static var previews: some View {
        AlbumView(onTransferToDevice: { _ in })
            .environmentObject(BleTransferService())
    }
}
