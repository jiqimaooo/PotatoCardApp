import Combine
import SwiftUI
import UIKit

@MainActor
final class CircleTransferCoordinator: ObservableObject {
    @Published var errorMessage: String?
    @Published var isPreparingTransfer = false

    private let apiClient: CircleAPIClient

    init(apiClient: CircleAPIClient) {
        self.apiClient = apiClient
    }

    func beginTransfer(post: CirclePost, bleService: BleTransferService) {
        beginTransfer(post: post, apiClient: apiClient, bleService: bleService)
    }

    func beginTransfer(post: CirclePost, apiClient: CircleAPIClient, accessToken: String? = nil, bleService: BleTransferService) {
        errorMessage = nil
        guard !isPreparingTransfer else { return }
        guard bleService.transferPhase != .preparing && bleService.transferPhase != .transferring else {
            errorMessage = BleTransferError.transferBusy.localizedDescription
            return
        }
        guard let device = bleService.connectedDevice ?? bleService.selectedDevice else {
            errorMessage = BleTransferError.deviceNotReady.localizedDescription
            return
        }

        isPreparingTransfer = true
        Task {
            do {
                let ticket = try await apiClient.transferTicket(postID: post.id, accessToken: accessToken)
                let image = try await apiClient.downloadTransferImage(from: ticket.downloadUrl)
                let displayImage = EInkImageRenderer.render(
                    image: image,
                    targetSize: device.profile.pixelSize,
                    fitMode: .centerCrop,
                    adjustment: .default
                )
                let transferImage = EInkImageRenderer.renderForTransfer(
                    image: image,
                    targetSize: device.profile.pixelSize,
                    fitMode: .centerCrop,
                    adjustment: .default,
                    profile: device.profile,
                    ditherAlgorithm: bleService.ditherAlgorithm
                )
                bleService.transfer(image: transferImage, displayImage: displayImage, to: device)
            } catch {
                errorMessage = error.localizedDescription
            }
            isPreparingTransfer = false
        }
    }
}
