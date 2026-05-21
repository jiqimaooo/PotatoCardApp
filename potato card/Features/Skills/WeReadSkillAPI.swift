import Foundation
import Security

enum WeReadAPIError: LocalizedError {
    case missingAPIKey
    case invalidRequestBody
    case invalidResponse
    case httpStatus(Int)
    case server(code: Int, message: String)
    case upgradeRequired(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先填写微信读书 API Key"
        case .invalidRequestBody:
            return "微信读书请求体无效"
        case .invalidResponse:
            return "微信读书响应无效"
        case .httpStatus(let status):
            return "微信读书请求失败：\(status)"
        case .server(_, let message):
            return message
        case .upgradeRequired(let message):
            return message
        }
    }
}

extension Notification.Name {
    static let weReadAPIKeyDidChange = Notification.Name("WeReadAPIKeyDidChange")
}

enum WeReadAPIKeyStore {
    private static let service = "com.sunbelife.potatocard.weread"
    private static let account = "weread_api_key"

    static func save(_ value: String) throws {
        let data = Data(value.utf8)
        try delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WeReadAPIError.server(code: Int(status), message: "微信读书 API Key 保存失败：\(status)")
        }
        NotificationCenter.default.post(name: .weReadAPIKeyDidChange, object: nil)
    }

    static func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw WeReadAPIError.server(code: Int(status), message: "微信读书 API Key 读取失败：\(status)")
        }

        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WeReadAPIError.server(code: Int(status), message: "微信读书 API Key 删除失败：\(status)")
        }
        NotificationCenter.default.post(name: .weReadAPIKeyDidChange, object: nil)
    }

    static func exists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}

struct WeReadGatewayClient {
    static let gatewayURL = URL(string: "https://i.weread.qq.com/api/agent/gateway")!
    static let skillVersion = "1.0.3"

    var apiKeyProvider: () -> String?
    var urlSession: URLSession = .shared

    init(
        apiKeyProvider: @escaping () -> String? = {
            try? WeReadAPIKeyStore.read()
        },
        urlSession: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.urlSession = urlSession
    }

    func verifyKey() async throws {
        _ = try await rawCall("/_list")
    }

    func listAPIs() async throws -> Any {
        try await rawCall("/_list")
    }

    func search(keyword: String, scope: Int = 10, maxIdx: Int? = nil, count: Int? = nil) async throws -> WeReadSearchResponse {
        var params: [String: Any] = [
            "keyword": keyword,
            "scope": scope
        ]
        if let maxIdx { params["maxIdx"] = maxIdx }
        if let count { params["count"] = count }
        return try await call("/store/search", params: params, as: WeReadSearchResponse.self)
    }

    func shelf() async throws -> WeReadShelfSyncResponse {
        try await call("/shelf/sync", as: WeReadShelfSyncResponse.self)
    }

    func bookInfo(bookId: String) async throws -> WeReadBookInfo {
        try await call("/book/info", params: ["bookId": bookId], as: WeReadBookInfo.self)
    }

    func bookChapters(bookId: String) async throws -> WeReadChapterInfoResponse {
        try await call("/book/chapterinfo", params: ["bookId": bookId], as: WeReadChapterInfoResponse.self)
    }

    func bookProgress(bookId: String) async throws -> WeReadBookProgressResponse {
        try await call("/book/getprogress", params: ["bookId": bookId], as: WeReadBookProgressResponse.self)
    }

    func readData(mode: WeReadReadDataMode = .monthly, baseTime: TimeInterval? = nil) async throws -> WeReadReadDataResponse {
        var params: [String: Any] = ["mode": mode.rawValue]
        if let baseTime { params["baseTime"] = Int(baseTime) }
        return try await call("/readdata/detail", params: params, as: WeReadReadDataResponse.self)
    }

    func notebooks(count: Int = 20, lastSort: Int? = nil) async throws -> WeReadNotebooksResponse {
        var params: [String: Any] = ["count": count]
        if let lastSort { params["lastSort"] = lastSort }
        return try await call("/user/notebooks", params: params, as: WeReadNotebooksResponse.self)
    }

    func bookmarkList(bookId: String, synckey: Int? = nil) async throws -> WeReadBookmarkListResponse {
        var params: [String: Any] = ["bookId": bookId]
        if let synckey { params["synckey"] = synckey }
        return try await call("/book/bookmarklist", params: params, as: WeReadBookmarkListResponse.self)
    }

    func myReviews(bookId: String, synckey: Int? = nil, count: Int = 20) async throws -> WeReadMineReviewsResponse {
        var params: [String: Any] = [
            "bookid": bookId,
            "count": count
        ]
        if let synckey { params["synckey"] = synckey }
        return try await call("/review/list/mine", params: params, as: WeReadMineReviewsResponse.self)
    }

    func publicReviews(
        bookId: String,
        reviewListType: Int = 0,
        count: Int = 20,
        maxIdx: Int? = nil,
        synckey: Int? = nil
    ) async throws -> WeReadPublicReviewsResponse {
        var params: [String: Any] = [
            "bookId": bookId,
            "reviewListType": reviewListType,
            "count": count
        ]
        if let maxIdx { params["maxIdx"] = maxIdx }
        if let synckey { params["synckey"] = synckey }
        return try await call("/review/list", params: params, as: WeReadPublicReviewsResponse.self)
    }

    func recommendations(count: Int = 12, maxIdx: Int? = nil) async throws -> WeReadRecommendationsResponse {
        var params: [String: Any] = ["count": count]
        if let maxIdx { params["maxIdx"] = maxIdx }
        return try await call("/book/recommend", params: params, as: WeReadRecommendationsResponse.self)
    }

    func similarBooks(bookId: String, count: Int = 12, maxIdx: Int? = nil, sessionId: String? = nil) async throws -> WeReadSimilarBooksResponse {
        var params: [String: Any] = [
            "bookId": bookId,
            "count": count
        ]
        if let maxIdx { params["maxIdx"] = maxIdx }
        if let sessionId { params["sessionId"] = sessionId }
        return try await call("/book/similar", params: params, as: WeReadSimilarBooksResponse.self)
    }

    func rawCall(_ apiName: String, params: [String: Any] = [:]) async throws -> Any {
        let data = try await perform(apiName: apiName, params: params)
        return try JSONSerialization.jsonObject(with: data)
    }

    func call<T: Decodable>(
        _ apiName: String,
        params: [String: Any] = [:],
        as type: T.Type = T.self
    ) async throws -> T {
        let data = try await perform(apiName: apiName, params: params)
        return try JSONDecoder().decode(type, from: data)
    }

    private func perform(apiName: String, params: [String: Any]) async throws -> Data {
        guard let apiKey = normalizedAPIKey() else {
            throw WeReadAPIError.missingAPIKey
        }

        var body = params
        body["api_name"] = apiName
        body["skill_version"] = Self.skillVersion

        guard JSONSerialization.isValidJSONObject(body) else {
            throw WeReadAPIError.invalidRequestBody
        }

        var request = URLRequest(url: Self.gatewayURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WeReadAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WeReadAPIError.httpStatus(http.statusCode)
        }

        let envelope = try? JSONDecoder().decode(WeReadGatewayEnvelope.self, from: data)
        if let upgradeMessage = envelope?.upgradeInfo?.message, !upgradeMessage.isEmpty {
            throw WeReadAPIError.upgradeRequired(upgradeMessage)
        }

        if let errcode = envelope?.errcode, errcode != 0 {
            let message = envelope?.errmsg?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WeReadAPIError.server(code: errcode, message: message?.isEmpty == false ? message! : "微信读书接口调用失败：\(errcode)")
        }

        return data
    }

    private func normalizedAPIKey() -> String? {
        let value = apiKeyProvider().flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? ""
        return value.isEmpty ? nil : value
    }
}

private struct WeReadGatewayEnvelope: Decodable {
    let errcode: Int?
    let errmsg: String?
    let upgradeInfo: WeReadGatewayUpgradeInfo?

    enum CodingKeys: String, CodingKey {
        case errcode
        case errmsg
        case upgradeInfo = "upgrade_info"
    }
}

private struct WeReadGatewayUpgradeInfo: Decodable {
    let message: String?
}

enum WeReadJSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: WeReadJSONValue])
    case array([WeReadJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: WeReadJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([WeReadJSONValue].self) {
            self = .array(value)
        } else {
            throw WeReadAPIError.invalidResponse
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct WeReadBookInfo: Decodable {
    let bookId: String
    let title: String
    let author: String?
    let translator: String?
    let cover: String?
    let intro: String?
    let category: String?
    let publisher: String?
    let publishTime: String?
    let isbn: String?
    let wordCount: Int?
    let newRating: Int?
    let newRatingCount: Int?
    let payType: Int?
    let price: Int?
    let soldout: Int?
}

struct WeReadSearchResponse: Decodable {
    let sid: String?
    let hasMore: Int?
    let results: [WeReadSearchGroup]
}

struct WeReadSearchGroup: Decodable {
    let title: String
    let scope: Int
    let scopeCount: Int?
    let currentCount: Int?
    let books: [WeReadSearchBook]
}

struct WeReadSearchBook: Decodable {
    let searchIdx: Int?
    let readingCount: Int?
    let newRating: Int?
    let newRatingCount: Int?
    let bookInfo: WeReadBookInfo
}

struct WeReadShelfSyncResponse: Decodable {
    let books: [WeReadShelfBook]
    let albums: [WeReadShelfAlbum]
    let mp: [String: WeReadJSONValue]?
    let archive: [WeReadShelfArchive]?
    let bookCount: Int?

    var totalCount: Int {
        books.count + albums.count + (mp?.isEmpty == false ? 1 : 0)
    }
}

struct WeReadShelfBook: Decodable {
    let bookId: String
    let title: String
    let author: String?
    let cover: String?
    let category: String?
    let readUpdateTime: Int?
    let finishReading: Int?
    let updateTime: Int?
    let isTop: Int?
    let secret: Int?
}

struct WeReadShelfAlbum: Decodable {
    let albumInfo: WeReadShelfAlbumInfo
    let albumInfoExtra: WeReadShelfAlbumExtra?
}

struct WeReadShelfAlbumInfo: Decodable {
    let albumId: String
    let name: String
    let authorName: String?
    let cover: String?
    let trackCount: Int?
    let finishStatus: String?
    let finish: Int?
    let payType: Int?
    let intro: String?
    let updateTime: Int?
}

struct WeReadShelfAlbumExtra: Decodable {
    let secret: Int?
    let lecturePaid: Int?
    let lectureReadUpdateTime: Int?
    let isTop: Int?
}

struct WeReadShelfArchive: Decodable {
    let name: String
    let bookIds: [String]
}

struct WeReadChapterInfoResponse: Decodable {
    let bookId: String
    let synckey: Int?
    let chapterUpdateTime: Int?
    let chapters: [WeReadChapterInfo]
}

struct WeReadChapterInfo: Decodable {
    let chapterUid: Int
    let chapterIdx: Int?
    let title: String
    let wordCount: Int?
    let level: Int?
    let updateTime: Int?
    let price: Int?
    let paid: Int?
    let isMPChapter: Int?
    let anchors: [WeReadChapterAnchor]?
}

struct WeReadChapterAnchor: Decodable {
    let title: String
    let level: Int?
}

struct WeReadBookProgressResponse: Decodable {
    let bookId: String
    let book: WeReadBookProgress
}

struct WeReadBookProgress: Decodable {
    let chapterUid: Int?
    let chapterOffset: Int?
    let progress: Int
    let updateTime: Int?
    let recordReadingTime: Int?
    let finishTime: Int?
    let isStartReading: Int?
}

enum WeReadReadDataMode: String {
    case weekly
    case monthly
    case annually
    case overall
}

struct WeReadReadDataResponse: Decodable {
    let baseTime: Int?
    let totalReadTime: Int
    let dayAverageReadTime: Int?
    let readDays: Int?
    let readTimes: [String: Int]?
    let dailyReadTimes: [String: Int]?
    let compare: Double?
    let readStat: [WeReadReadStat]?
    let readLongest: [[String: WeReadJSONValue]]?
    let preferCategory: [[String: WeReadJSONValue]]?
    let preferTime: [Int]?
    let preferTimeWord: String?
    let preferAuthor: [[String: WeReadJSONValue]]?
    let authorCount: Int?
    let preferPublisher: [[String: WeReadJSONValue]]?
}

struct WeReadReadStat: Decodable {
    let stat: String
    let counts: String
    let scheme: String?
}

struct WeReadNotebooksResponse: Decodable {
    let totalBookCount: Int
    let totalNoteCount: Int
    let hasMore: Int
    let books: [WeReadNotebookBook]
}

struct WeReadNotebookBook: Decodable {
    let bookId: String
    let book: WeReadNotebookBookInfo
    let reviewCount: Int
    let noteCount: Int
    let bookmarkCount: Int
    let readingProgress: Int?
    let markedStatus: Int?
    let sort: Int

    var totalPersonalNoteCount: Int {
        reviewCount + noteCount + bookmarkCount
    }
}

struct WeReadNotebookBookInfo: Decodable {
    let bookId: String
    let title: String
    let author: String?
    let cover: String?
}

struct WeReadBookmarkListResponse: Decodable {
    let book: WeReadBookmarkBook?
    let chapters: [WeReadBookmarkChapter]?
    let updated: [WeReadBookmark]
}

struct WeReadBookmarkBook: Decodable {
    let bookId: String
    let title: String?
}

struct WeReadBookmarkChapter: Decodable {
    let chapterUid: Int
    let chapterIdx: Int?
    let title: String?
}

struct WeReadBookmark: Decodable {
    let bookmarkId: String
    let bookId: String
    let chapterUid: Int?
    let range: String
    let markText: String
    let createTime: Int?
    let type: Int?
}

struct WeReadMineReviewsResponse: Decodable {
    let totalCount: Int
    let hasMore: Int
    let synckey: Int
    let reviews: [WeReadMineReviewContainer]
}

struct WeReadMineReviewContainer: Decodable {
    let review: WeReadMineReview
}

struct WeReadMineReview: Decodable {
    let reviewId: String
    let content: String
    let createTime: Int?
    let star: Int?
    let chapterName: String?
    let isFinish: Int?
    let range: String?
    let chapterUid: Int?
    let abstract: String?
}

struct WeReadPublicReviewsResponse: Decodable {
    let synckey: Int?
    let reviewsCnt: Int?
    let recentTotalCnt: Int?
    let reviewsHasMore: Int?
    let friendCommentCount: Int?
    let reviews: [WeReadPublicReviewItem]
}

struct WeReadPublicReviewItem: Decodable {
    let idx: Int?
    let review: WeReadPublicReviewWrapper
}

struct WeReadPublicReviewWrapper: Decodable {
    let review: WeReadPublicReview
}

struct WeReadPublicReview: Decodable {
    let reviewId: String
    let content: String
    let htmlContent: String?
    let star: Int?
    let isFinish: Int?
    let createTime: Int?
    let chapterName: String?
    let author: WeReadReviewAuthor
    let book: WeReadReviewBook
}

struct WeReadReviewAuthor: Decodable {
    let userVid: String
    let name: String
    let avatar: String?
}

struct WeReadReviewBook: Decodable {
    let bookId: String
    let title: String?
    let author: String?
}

struct WeReadRecommendationsResponse: Decodable {
    let books: [WeReadRecommendedBook]
}

struct WeReadRecommendedBook: Decodable {
    let bookId: String
    let title: String
    let author: String?
    let cover: String?
    let intro: String?
    let category: String?
    let reason: String?
    let readingCount: Int?
    let searchIdx: Int?
    let newRating: Int?
    let newRatingCount: Int?
    let price: Int?
    let payType: Int?
}

struct WeReadSimilarBooksResponse: Decodable {
    let booksimilar: WeReadSimilarBooksPayload
}

struct WeReadSimilarBooksPayload: Decodable {
    let sessionId: String
    let books: [WeReadSimilarBook]
}

struct WeReadSimilarBook: Decodable {
    let idx: Int?
    let book: WeReadSimilarBookInfo
}

struct WeReadSimilarBookInfo: Decodable {
    let bookInfo: WeReadBookInfo
}
