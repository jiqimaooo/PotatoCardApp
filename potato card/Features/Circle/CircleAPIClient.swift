import Foundation
import UIKit

enum CircleAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case missingAuthToken
    case unauthorized
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器响应无效"
        case .httpStatus(let status):
            return "服务器请求失败：\(status)"
        case .missingAuthToken:
            return "登录状态已失效，请重新登录"
        case .unauthorized:
            return "登录状态已失效，请重新登录"
        case .serverMessage(let message):
            return message
        }
    }
}

struct CircleAPIClient {
    var baseURL: URL
    var tokenProvider: () -> String?
    var urlSession: URLSession = .shared

    func createRegisterOptions(rawDeviceIdentifier: String, username: String) async throws -> CirclePasskeyRegistrationOptions {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/register/options"))
        request.httpMethod = "POST"
        request.setJSONBody([
            "rawDeviceIdentifier": rawDeviceIdentifier,
            "username": username,
        ])
        let data = try await perform(request)
        return try JSONDecoder().decode(CirclePasskeyRegistrationOptions.self, from: data)
    }

    func verifyRegistration(
        rawDeviceIdentifier: String,
        username: String,
        avatarKey: String,
        challenge: String,
        response: CirclePasskeyRegistrationResponse
    ) async throws -> CircleAuthSession {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/register/verify"))
        request.httpMethod = "POST"
        request.setJSONBody(RegisterVerifyBody(
            rawDeviceIdentifier: rawDeviceIdentifier,
            username: username,
            avatarKey: avatarKey,
            challenge: challenge,
            response: response
        ))
        let data = try await perform(request)
        return try JSONDecoder().decode(CircleAuthSession.self, from: data)
    }

    func registerWithPassword(rawDeviceIdentifier: String, username: String, password: String, avatarKey: String) async throws -> CircleAuthSession {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/password/register"))
        request.httpMethod = "POST"
        request.setJSONBody([
            "rawDeviceIdentifier": rawDeviceIdentifier,
            "username": username,
            "password": password,
            "avatarKey": avatarKey,
        ])
        let data = try await perform(request)
        return try JSONDecoder().decode(CircleAuthSession.self, from: data)
    }

    func uploadAvatar(imageData: Data) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/avatar"))
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = avatarMultipartBody(boundary: boundary, imageData: imageData)
        let data = try await perform(request)
        return try JSONDecoder().decode(CircleAvatarUploadResponse.self, from: data).avatarKey
    }

    func updateProfileAvatar(avatarKey: String, accessToken: String? = nil) async throws -> CircleUserProfile {
        var request = URLRequest(url: baseURL.appendingPathComponent("me/avatar"))
        request.httpMethod = "POST"
        try attachRequiredAuth(to: &request, accessToken: accessToken)
        request.setJSONBody(UpdateAvatarBody(avatarKey: avatarKey))
        let data = try await perform(request)
        return try JSONDecoder().decode(CircleUserProfile.self, from: data)
    }

    func changePassword(currentPassword: String, newPassword: String, accessToken: String? = nil) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("me/password"))
        request.httpMethod = "POST"
        try attachRequiredAuth(to: &request, accessToken: accessToken)
        request.setJSONBody(ChangePasswordBody(currentPassword: currentPassword, newPassword: newPassword))
        _ = try await perform(request)
    }

    func loginWithPassword(username: String, password: String) async throws -> CircleAuthSession {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/password/login"))
        request.httpMethod = "POST"
        request.setJSONBody([
            "username": username,
            "password": password,
        ])
        let data = try await perform(request)
        return try JSONDecoder().decode(CircleAuthSession.self, from: data)
    }

    func refreshSession(refreshToken: String) async throws -> CircleAuthSession {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/refresh"))
        request.httpMethod = "POST"
        request.setJSONBody(["refreshToken": refreshToken])
        let data = try await perform(request)
        return try JSONDecoder().decode(CircleAuthSession.self, from: data)
    }

    func fetchPosts(cursor: String? = nil) async throws -> CircleFeedResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("community/posts"), resolvingAgainstBaseURL: false)
        if let cursor, !cursor.isEmpty {
            components?.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        }
        guard let url = components?.url else {
            throw CircleAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        attachAuth(to: &request)
        let data = try await perform(request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CircleFeedResponse.self, from: data)
    }

    func transferTicket(postID: String, accessToken: String? = nil) async throws -> CircleTransferTicket {
        var request = URLRequest(url: baseURL.appendingPathComponent("community/posts/\(postID)/transfer-ticket"))
        request.httpMethod = "POST"
        try attachRequiredAuth(to: &request, accessToken: accessToken)
        let data = try await perform(request)
        return try JSONDecoder().decode(CircleTransferTicket.self, from: data)
    }

    func createPost(imageData: Data, title: String, tags: [String], accessToken: String? = nil) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("community/posts"))
        request.httpMethod = "POST"
        try attachRequiredAuth(to: &request, accessToken: accessToken)
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, imageData: imageData, title: title, tags: tags)
        _ = try await perform(request)
    }

    func createDriftBottle(imageData: Data, accessToken: String? = nil) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("community/drift-bottles"))
        request.httpMethod = "POST"
        try attachRequiredAuth(to: &request, accessToken: accessToken)
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageOnlyMultipartBody(boundary: boundary, imageData: imageData)
        _ = try await perform(request)
    }

    func drawDriftBottle(accessToken: String? = nil) async throws -> CircleDriftBottleDrawResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("community/drift-bottles/draw"))
        request.httpMethod = "POST"
        try attachRequiredAuth(to: &request, accessToken: accessToken)
        let data = try await perform(request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CircleDriftBottleDrawResponse.self, from: data)
    }

    func createImageToken(
        imageData: Data,
        tokenCode: String?,
        isBurnAfterRead: Bool,
        expiresInHours: Int,
        accessToken: String? = nil
    ) async throws -> CircleImageToken {
        var request = URLRequest(url: baseURL.appendingPathComponent("community/image-tokens"))
        request.httpMethod = "POST"
        try attachRequiredAuth(to: &request, accessToken: accessToken)
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageTokenMultipartBody(
            boundary: boundary,
            imageData: imageData,
            tokenCode: tokenCode,
            isBurnAfterRead: isBurnAfterRead,
            expiresInHours: expiresInHours
        )
        let data = try await perform(request)
        return try imageTokenDecoder.decode(CircleImageToken.self, from: data)
    }

    func claimImageToken(tokenCode: String, accessToken: String? = nil) async throws -> CircleImageToken {
        var request = URLRequest(url: baseURL.appendingPathComponent("community/image-tokens/claim"))
        request.httpMethod = "POST"
        try attachRequiredAuth(to: &request, accessToken: accessToken)
        request.setJSONBody(["tokenCode": tokenCode])
        let data = try await perform(request)
        return try imageTokenDecoder.decode(CircleImageToken.self, from: data)
    }

    func fetchReceivedImageTokens(accessToken: String? = nil) async throws -> [CircleImageToken] {
        var request = URLRequest(url: baseURL.appendingPathComponent("community/image-tokens/received"))
        try attachRequiredAuth(to: &request, accessToken: accessToken)
        let data = try await perform(request)
        return try imageTokenDecoder.decode(CircleImageTokenListResponse.self, from: data).items
    }

    func downloadImageTokenTransferImage(id: String, accessToken: String? = nil) async throws -> UIImage {
        var request = URLRequest(url: baseURL.appendingPathComponent("community/image-tokens/\(id)/transfer-image"))
        try attachRequiredAuth(to: &request, accessToken: accessToken)
        let data = try await perform(request)
        guard let image = UIImage(data: data) else { throw CircleAPIError.invalidResponse }
        return image
    }

    func recordImageTokenTransfer(id: String, deviceID: String?, accessToken: String? = nil) async throws -> CircleImageToken {
        var request = URLRequest(url: baseURL.appendingPathComponent("community/image-tokens/\(id)/transfer-events"))
        request.httpMethod = "POST"
        try attachRequiredAuth(to: &request, accessToken: accessToken)
        request.setJSONBody(ImageTokenTransferEventBody(deviceId: deviceID))
        let data = try await perform(request)
        return try imageTokenDecoder.decode(CircleImageToken.self, from: data)
    }

    func downloadTransferImage(from url: URL) async throws -> UIImage {
        let (data, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw CircleAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw CircleAPIError.httpStatus(http.statusCode) }
        guard let image = UIImage(data: data) else { throw CircleAPIError.invalidResponse }
        return image
    }

    private func attachAuth(to request: inout URLRequest) {
        guard let token = normalizedToken(tokenProvider()) else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func attachRequiredAuth(to request: inout URLRequest, accessToken: String?) throws {
        guard let token = normalizedToken(accessToken) ?? normalizedToken(tokenProvider()) else {
            throw CircleAPIError.missingAuthToken
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func normalizedToken(_ token: String?) -> String? {
        let value = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CircleAPIError.invalidResponse }
        if http.statusCode == 401 { throw CircleAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            if let message = serverErrorMessage(from: data) {
                throw CircleAPIError.serverMessage(message)
            }
            throw CircleAPIError.httpStatus(http.statusCode)
        }
        return data
    }

    private func serverErrorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawMessage = object["message"]
        else {
            return nil
        }
        if let message = rawMessage as? String, !message.isEmpty {
            return message
        }
        if let messages = rawMessage as? [String], let message = messages.first, !message.isEmpty {
            return message
        }
        return nil
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

    private func avatarMultipartBody(boundary: String, imageData: Data) -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"image\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        data.append(imageData)
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }

    private func imageOnlyMultipartBody(boundary: String, imageData: Data) -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"image\"; filename=\"drift-bottle.jpg\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        data.append(imageData)
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }

    private func imageTokenMultipartBody(
        boundary: String,
        imageData: Data,
        tokenCode: String?,
        isBurnAfterRead: Bool,
        expiresInHours: Int
    ) -> Data {
        var data = Data()
        if let tokenCode, !tokenCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendField("tokenCode", tokenCode, boundary: boundary, to: &data)
        }
        appendField("isBurnAfterRead", isBurnAfterRead ? "true" : "false", boundary: boundary, to: &data)
        appendField("expiresInHours", "\(expiresInHours)", boundary: boundary, to: &data)
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"image\"; filename=\"image-token.jpg\"\r\n".data(using: .utf8)!)
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

    private var imageTokenDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private struct RegisterVerifyBody: Encodable {
        let rawDeviceIdentifier: String
        let username: String
        let avatarKey: String
        let challenge: String
        let response: CirclePasskeyRegistrationResponse
    }

    private struct CircleAvatarUploadResponse: Decodable {
        let avatarKey: String
    }

    private struct UpdateAvatarBody: Encodable {
        let avatarKey: String
    }

    private struct ChangePasswordBody: Encodable {
        let currentPassword: String
        let newPassword: String
    }

    private struct ImageTokenTransferEventBody: Encodable {
        let deviceId: String?
    }
}

private extension URLRequest {
    mutating func setJSONBody<T: Encodable>(_ body: T) {
        setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpBody = try? JSONEncoder().encode(body)
    }
}
