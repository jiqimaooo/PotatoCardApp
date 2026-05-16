import Foundation
import UIKit

enum CircleAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器响应无效"
        case .httpStatus(let status):
            return "服务器请求失败：\(status)"
        }
    }
}

struct CircleAPIClient {
    var baseURL: URL
    var tokenProvider: () -> String?
    var urlSession: URLSession = .shared

    func fetchPosts() async throws -> [CirclePost] {
        var request = URLRequest(url: baseURL.appendingPathComponent("community/posts"))
        attachAuth(to: &request)
        let data = try await perform(request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CircleFeedResponse.self, from: data).items
    }

    func transferTicket(postID: String) async throws -> CircleTransferTicket {
        var request = URLRequest(url: baseURL.appendingPathComponent("community/posts/\(postID)/transfer-ticket"))
        request.httpMethod = "POST"
        attachAuth(to: &request)
        let data = try await perform(request)
        return try JSONDecoder().decode(CircleTransferTicket.self, from: data)
    }

    func createPost(imageData: Data, title: String, tags: [String]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("community/posts"))
        request.httpMethod = "POST"
        attachAuth(to: &request)
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, imageData: imageData, title: title, tags: tags)
        _ = try await perform(request)
    }

    func downloadTransferImage(from url: URL) async throws -> UIImage {
        let (data, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw CircleAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw CircleAPIError.httpStatus(http.statusCode) }
        guard let image = UIImage(data: data) else { throw CircleAPIError.invalidResponse }
        return image
    }

    private func attachAuth(to request: inout URLRequest) {
        guard let token = tokenProvider() else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CircleAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw CircleAPIError.httpStatus(http.statusCode) }
        return data
    }

    private func multipartBody(boundary: String, imageData: Data, title: String, tags: [String]) -> Data {
        var data = Data()
        appendField("title", title, boundary: boundary, to: &data)
        appendField("tags", tags.joined(separator: ","), boundary: boundary, to: &data)
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"image\"; filename=\"post.jpg\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        data.append(imageData)
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }

    private func appendField(_ name: String, _ value: String, boundary: String, to data: inout Data) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(value)\r\n".data(using: .utf8)!)
    }
}
