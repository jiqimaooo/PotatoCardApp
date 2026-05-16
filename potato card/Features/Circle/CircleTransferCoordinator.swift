import Combine
import SwiftUI
import UIKit

@MainActor
final class CircleTransferCoordinator: ObservableObject {
    @Published var transferRequest: CircleTransferRequest?
    @Published var errorMessage: String?

    private let apiClient: CircleAPIClient

    init(apiClient: CircleAPIClient) {
        self.apiClient = apiClient
    }

    func beginTransfer(post: CirclePost) {
        errorMessage = nil
        Task {
            do {
                let ticket = try await apiClient.transferTicket(postID: post.id)
                let image = try await apiClient.downloadTransferImage(from: ticket.downloadUrl)
                transferRequest = CircleTransferRequest(post: post, image: image)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct CircleTransferRequest: Identifiable {
    let id = UUID()
    let post: CirclePost
    let image: UIImage
}
