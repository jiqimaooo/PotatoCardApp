import Combine
import SafariServices
import SwiftUI
import UIKit

@MainActor
final class WeReadSkillSetupStore: ObservableObject {
    enum StatusTone {
        case neutral
        case success
        case warning
    }

    let tokenPageURL = URL(string: "https://weread.qq.com/r/weread-skills")!

    @Published var apiKeyInput = ""
    @Published var hasSavedKey = false
    @Published var isVerifying = false
    @Published var isKeyVisible = false
    @Published var statusText = "打开官方页面生成 Key，回到这里粘贴保存。"
    @Published var statusTone: StatusTone = .neutral
    @Published var toastMessage: String?
    @Published var isLoadingPreviewData = false
    @Published var previewSnapshot: WeReadPreviewSnapshot?

    init() {
        reloadSavedKey()
    }

    var savedKeyPreview: String {
        let value = apiKeyInput.trimmed
        guard !value.isEmpty else { return "等待填写" }
        guard value.count > 12 else { return value }
        let prefix = value.prefix(6)
        let suffix = value.suffix(4)
        return "\(prefix)••••\(suffix)"
    }

    func reloadSavedKey() {
        let savedValue = (try? WeReadAPIKeyStore.read())?.trimmed ?? ""
        hasSavedKey = !savedValue.isEmpty
        if !savedValue.isEmpty {
            apiKeyInput = savedValue
            statusText = "本机已保存微信读书 Key。"
            statusTone = .success
        } else if apiKeyInput.trimmed.isEmpty {
            statusText = "打开官方页面生成 Key，回到这里粘贴保存。"
            statusTone = .neutral
        }
    }

    func copyTokenPageLink() {
        UIPasteboard.general.string = tokenPageURL.absoluteString
        toastMessage = "领 Key 链接已复制"
    }

    func pasteAndSaveFromClipboard() {
        guard let rawValue = UIPasteboard.general.string?.trimmed, !rawValue.isEmpty else {
            statusText = "剪贴板里还没有微信读书 Key。"
            statusTone = .warning
            return
        }

        let token = extractToken(from: rawValue) ?? rawValue
        apiKeyInput = token
        saveCurrentKey()
    }

    func saveCurrentKey() {
        let value = apiKeyInput.trimmed
        guard !value.isEmpty else {
            statusText = "填写 Key 后即可保存。"
            statusTone = .warning
            return
        }

        guard value.hasPrefix("wrk-") else {
            statusText = "Key 格式需要以 wrk- 开头。"
            statusTone = .warning
            return
        }

        do {
            try WeReadAPIKeyStore.save(value)
            apiKeyInput = value
            hasSavedKey = true
            statusText = "Key 已保存到本机 Keychain。"
            statusTone = .success
            toastMessage = "保存完成"
        } catch {
            statusText = error.localizedDescription
            statusTone = .warning
        }
    }

    func clearSavedKey() {
        do {
            try WeReadAPIKeyStore.delete()
            apiKeyInput = ""
            hasSavedKey = false
            statusText = "本机 Key 已清空。"
            statusTone = .neutral
            toastMessage = "已清空"
        } catch {
            statusText = error.localizedDescription
            statusTone = .warning
        }
    }

    func verifyCurrentKey() async {
        let value = apiKeyInput.trimmed
        guard !value.isEmpty else {
            statusText = "填写 Key 后即可校验。"
            statusTone = .warning
            return
        }

        guard value.hasPrefix("wrk-") else {
            statusText = "Key 格式需要以 wrk- 开头。"
            statusTone = .warning
            return
        }

        saveCurrentKey()
        isVerifying = true
        statusText = "正在校验微信读书连接..."
        statusTone = .neutral

        defer {
            isVerifying = false
        }

        do {
            try await WeReadGatewayClient(apiKeyProvider: { value }).verifyKey()
            statusText = "校验通过，可以读取书架、笔记、书评、推荐和阅读统计。"
            statusTone = .success
            toastMessage = "微信读书已接入"
            await refreshPreviewData()
        } catch {
            statusText = error.localizedDescription
            statusTone = .warning
        }
    }

    func refreshPreviewData() async {
        let value = apiKeyInput.trimmed
        guard !value.isEmpty else {
            statusText = "填写 Key 后即可读取微信读书数据。"
            statusTone = .warning
            return
        }

        saveCurrentKey()
        isLoadingPreviewData = true
        statusText = "正在读取微信读书数据..."
        statusTone = .neutral

        defer {
            isLoadingPreviewData = false
        }

        do {
            let client = WeReadGatewayClient(apiKeyProvider: { value })
            var loadErrors: [String] = []
            let shelf: WeReadShelfSyncResponse? = await loadPreviewPart("书架", errors: &loadErrors) {
                try await client.shelf()
            }
            let readData: WeReadReadDataResponse? = await loadPreviewPart("阅读统计", errors: &loadErrors) {
                try await client.readData(mode: .monthly)
            }
            let notebooks: WeReadNotebooksResponse? = await loadPreviewPart("笔记", errors: &loadErrors) {
                try await client.notebooks(count: 10)
            }
            let dailyBookmarks = await loadDailyBookmarks(
                from: notebooks,
                client: client,
                errors: &loadErrors
            )
            let recommendations: WeReadRecommendationsResponse? = await loadPreviewPart("推荐", errors: &loadErrors) {
                try await client.recommendations(count: 8)
            }

            let snapshot = WeReadPreviewSnapshot(
                shelf: shelf,
                readData: readData,
                notebooks: notebooks,
                dailyBookmarks: dailyBookmarks,
                dailyBookmarkIndex: 0,
                recommendations: recommendations
            )
            previewSnapshot = snapshot
            if loadErrors.isEmpty {
                statusText = "已读取书架、阅读统计、笔记和推荐，可预览后传输到土豆片。"
                statusTone = .success
                toastMessage = "读取完成"
            } else if snapshot.hasAnyData {
                statusText = "已读取部分数据：\(loadErrors.joined(separator: "、")) 暂不可用。"
                statusTone = .warning
                toastMessage = "已读取部分数据"
            } else {
                statusText = "Key 可用，但暂时没有读到微信读书数据：\(loadErrors.joined(separator: "、"))。"
                statusTone = .warning
            }
        }
    }

    func showNextDailyBookmark() {
        guard let snapshot = previewSnapshot, snapshot.dailyBookmarks.count > 1 else {
            toastMessage = "还没有更多划线"
            return
        }
        previewSnapshot = snapshot.withDailyBookmarkIndex(snapshot.dailyBookmarkIndex + 1)
    }

    private func loadPreviewPart<T>(
        _ name: String,
        errors: inout [String],
        operation: () async throws -> T
    ) async -> T? {
        do {
            return try await operation()
        } catch {
            errors.append(name)
            print("WeRead preview \(name) failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func loadDailyBookmarks(
        from notebooks: WeReadNotebooksResponse?,
        client: WeReadGatewayClient,
        errors: inout [String]
    ) async -> [WeReadDailyBookmark] {
        guard let book = notebooks?.books.max(by: { lhs, rhs in
            lhs.totalPersonalNoteCount < rhs.totalPersonalNoteCount
        }) else {
            return []
        }

        let response: WeReadBookmarkListResponse? = await loadPreviewPart("每日划线", errors: &errors) {
            try await client.bookmarkList(bookId: book.bookId)
        }
        let chapters = response?.chapters ?? []
        return (response?.updated ?? [])
            .filter { !$0.markText.trimmed.isEmpty }
            .map { bookmark in
                WeReadDailyBookmark(
                    text: bookmark.markText,
                    bookTitle: book.book.title,
                    author: book.book.author,
                    chapterName: chapters.first(where: { $0.chapterUid == bookmark.chapterUid })?.title,
                    createTime: bookmark.createTime
                )
            }
    }

    private func extractToken(from rawValue: String) -> String? {
        let pattern = #"wrk-[A-Za-z0-9\-_]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(rawValue.startIndex..<rawValue.endIndex, in: rawValue)
        guard let match = regex.firstMatch(in: rawValue, options: [], range: range),
              let tokenRange = Range(match.range, in: rawValue) else {
            return nil
        }
        return String(rawValue[tokenRange])
    }
}

struct WeReadPreviewSnapshot {
    let shelfTotalCount: Int
    let recentBooks: [WeReadShelfBook]
    let monthlyReadMinutes: Int
    let dayAverageReadMinutes: Int?
    let readDays: Int?
    let notebookBookCount: Int
    let totalNoteCount: Int
    let topNotebook: WeReadNotebookBook?
    let dailyBookmarks: [WeReadDailyBookmark]
    let dailyBookmarkIndex: Int
    let recommendedBooks: [WeReadRecommendedBook]
    let updatedAt: Date

    init(
        shelf: WeReadShelfSyncResponse?,
        readData: WeReadReadDataResponse?,
        notebooks: WeReadNotebooksResponse?,
        dailyBookmarks: [WeReadDailyBookmark],
        dailyBookmarkIndex: Int,
        recommendations: WeReadRecommendationsResponse?
    ) {
        shelfTotalCount = shelf?.bookCount ?? shelf?.totalCount ?? 0
        recentBooks = (shelf?.books ?? [])
            .sorted { lhs, rhs in
                (lhs.readUpdateTime ?? lhs.updateTime ?? 0) > (rhs.readUpdateTime ?? rhs.updateTime ?? 0)
            }
            .prefix(5)
            .map { $0 }
        monthlyReadMinutes = readData.map { Self.readMinutes(from: $0.totalReadTime) } ?? 0
        dayAverageReadMinutes = readData?.dayAverageReadTime.map(Self.readMinutes(from:))
        readDays = readData?.readDays
        notebookBookCount = notebooks?.totalBookCount ?? 0
        totalNoteCount = notebooks?.totalNoteCount ?? 0
        topNotebook = notebooks?.books.max { lhs, rhs in
            lhs.totalPersonalNoteCount < rhs.totalPersonalNoteCount
        }
        self.dailyBookmarks = dailyBookmarks
        self.dailyBookmarkIndex = dailyBookmarks.isEmpty ? 0 : dailyBookmarkIndex % dailyBookmarks.count
        recommendedBooks = (recommendations?.books ?? []).prefix(5).map { $0 }
        updatedAt = Date()
    }

    var hasAnyData: Bool {
        shelfTotalCount > 0 || monthlyReadMinutes > 0 || totalNoteCount > 0 || !dailyBookmarks.isEmpty || !recommendedBooks.isEmpty
    }

    var dailyBookmark: WeReadDailyBookmark? {
        guard !dailyBookmarks.isEmpty else { return nil }
        return dailyBookmarks[dailyBookmarkIndex % dailyBookmarks.count]
    }

    func withDailyBookmarkIndex(_ index: Int) -> WeReadPreviewSnapshot {
        WeReadPreviewSnapshot(
            shelfTotalCount: shelfTotalCount,
            recentBooks: recentBooks,
            monthlyReadMinutes: monthlyReadMinutes,
            dayAverageReadMinutes: dayAverageReadMinutes,
            readDays: readDays,
            notebookBookCount: notebookBookCount,
            totalNoteCount: totalNoteCount,
            topNotebook: topNotebook,
            dailyBookmarks: dailyBookmarks,
            dailyBookmarkIndex: index,
            recommendedBooks: recommendedBooks,
            updatedAt: Date()
        )
    }

    var recentBookLine: String {
        guard let book = recentBooks.first else { return "书架暂无最近阅读记录" }
        return "\(book.title) · \(book.author ?? "未知作者")"
    }

    var readDaysText: String {
        guard let readDays else { return "阅读天数未知" }
        return "阅读 \(readDays) 天"
    }

    nonisolated private static func readMinutes(from rawValue: Int) -> Int {
        max(0, rawValue / 60)
    }

    private init(
        shelfTotalCount: Int,
        recentBooks: [WeReadShelfBook],
        monthlyReadMinutes: Int,
        dayAverageReadMinutes: Int?,
        readDays: Int?,
        notebookBookCount: Int,
        totalNoteCount: Int,
        topNotebook: WeReadNotebookBook?,
        dailyBookmarks: [WeReadDailyBookmark],
        dailyBookmarkIndex: Int,
        recommendedBooks: [WeReadRecommendedBook],
        updatedAt: Date
    ) {
        self.shelfTotalCount = shelfTotalCount
        self.recentBooks = recentBooks
        self.monthlyReadMinutes = monthlyReadMinutes
        self.dayAverageReadMinutes = dayAverageReadMinutes
        self.readDays = readDays
        self.notebookBookCount = notebookBookCount
        self.totalNoteCount = totalNoteCount
        self.topNotebook = topNotebook
        self.dailyBookmarks = dailyBookmarks
        self.dailyBookmarkIndex = dailyBookmarks.isEmpty ? 0 : dailyBookmarkIndex % dailyBookmarks.count
        self.recommendedBooks = recommendedBooks
        self.updatedAt = updatedAt
    }
}

struct WeReadDailyBookmark {
    let text: String
    let bookTitle: String
    let author: String?
    let chapterName: String?
    let createTime: Int?
}

enum WeReadPreviewTemplate: String, CaseIterable, Identifiable {
    case dailyQuote
    case monthlySummary

    static let allCases: [WeReadPreviewTemplate] = [.dailyQuote, .monthlySummary]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailyQuote:
            return "每日划线"
        case .monthlySummary:
            return "阅读月报"
        }
    }

    var iconName: String {
        switch self {
        case .dailyQuote:
            return "quote.bubble.fill"
        case .monthlySummary:
            return "clock.arrow.circlepath"
        }
    }
}

private struct WeReadDataRow: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let value: String
    let detail: String?
}

struct WeReadOfficialIcon: View {
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Image("weread_icon")
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .frame(width: size, height: size)
        .accessibilityLabel("微信读书")
    }
}

enum WeReadSkillRenderer {
    private enum Layout {
        static let canvasSize = CGSize(width: 400, height: 600)
        static let margin: CGFloat = 22
    }

    private enum Palette {
        static let background = UIColor(red: 0.95, green: 0.97, blue: 0.94, alpha: 1)
        static let ink = UIColor(white: 0.08, alpha: 1)
        static let muted = UIColor(white: 0.32, alpha: 1)
        static let green = UIColor(red: 0.10, green: 0.63, blue: 0.48, alpha: 1)
        static let blue = UIColor(red: 0.18, green: 0.49, blue: 0.98, alpha: 1)
        static let orange = UIColor(red: 0.94, green: 0.52, blue: 0.17, alpha: 1)
        static let panel = UIColor.white
    }

    static func renderPlaceholder(template: WeReadPreviewTemplate) -> UIImage {
        renderBase { context in
            drawHeader(title: template.title, updatedAt: Date(), in: context)
            drawText(
                "等待读取数据",
                font: .systemFont(ofSize: 34, weight: .bold),
                color: Palette.ink,
                rect: CGRect(x: Layout.margin, y: 230, width: 356, height: 46),
                alignment: .center
            )
            drawText(
                "保存 Key 后读取书架、阅读统计和笔记，再传输到土豆片。",
                font: .systemFont(ofSize: 19, weight: .medium),
                color: Palette.muted,
                rect: CGRect(x: 44, y: 286, width: 312, height: 80),
                alignment: .center
            )
        }
    }

    static func render(snapshot: WeReadPreviewSnapshot, template: WeReadPreviewTemplate) -> UIImage {
        renderBase { context in
            switch template {
            case .dailyQuote:
                drawDailyQuote(snapshot: snapshot, in: context)
            case .monthlySummary:
                drawHeader(title: "阅读月报", updatedAt: snapshot.updatedAt, in: context)
                drawMainMetric(snapshot: snapshot, in: context)
                drawRecentBooks(snapshot.recentBooks, in: context)
                drawNotes(snapshot: snapshot, in: context)
                drawRecommendations(snapshot.recommendedBooks, in: context)
            }
        }
    }

    private static func renderBase(_ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: Layout.canvasSize, format: format)
        return renderer.image { rendererContext in
            let context = rendererContext.cgContext
            Palette.background.setFill()
            context.fill(CGRect(origin: .zero, size: Layout.canvasSize))
            draw(context)
        }
    }

    private static func drawHeader(title: String, updatedAt: Date, in context: CGContext) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"

        drawText(
            title,
            font: .systemFont(ofSize: 31, weight: .heavy),
            color: Palette.ink,
            rect: CGRect(x: Layout.margin, y: 24, width: 190, height: 40),
            alignment: .left
        )
        drawText(
            formatter.string(from: updatedAt),
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: Palette.muted,
            rect: CGRect(x: 198, y: 33, width: 180, height: 22),
            alignment: .right
        )
        drawLine(from: CGPoint(x: Layout.margin, y: 82), to: CGPoint(x: 378, y: 82), color: Palette.ink, width: 2, in: context)
    }

    private static func drawMainMetric(snapshot: WeReadPreviewSnapshot, in context: CGContext) {
        drawText(
            "\(snapshot.monthlyReadMinutes / 60)",
            font: .systemFont(ofSize: 88, weight: .heavy),
            color: Palette.ink,
            rect: CGRect(x: Layout.margin, y: 104, width: 126, height: 96),
            alignment: .left
        )
        drawText(
            "h \(snapshot.monthlyReadMinutes % 60)m",
            font: .systemFont(ofSize: 27, weight: .bold),
            color: Palette.green,
            rect: CGRect(x: 144, y: 151, width: 120, height: 38),
            alignment: .left
        )
        drawText(
            "本月阅读",
            font: .systemFont(ofSize: 21, weight: .bold),
            color: Palette.ink,
            rect: CGRect(x: 254, y: 112, width: 124, height: 30),
            alignment: .right
        )
        drawText(
            "\(snapshot.readDaysText)\n书架 \(snapshot.shelfTotalCount) 本",
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: Palette.muted,
            rect: CGRect(x: 222, y: 148, width: 156, height: 54),
            alignment: .right
        )
        drawLine(from: CGPoint(x: Layout.margin, y: 224), to: CGPoint(x: 378, y: 224), color: UIColor(white: 0.55, alpha: 1), width: 1, in: context)
    }

    private static func drawRecentBooks(_ books: [WeReadShelfBook], in context: CGContext) {
        drawSectionTitle("最近阅读", y: 246)
        let displayBooks = books.prefix(3)
        for (index, book) in displayBooks.enumerated() {
            let y = 286 + CGFloat(index) * 42
            drawDot(color: index == 0 ? Palette.green : Palette.blue, center: CGPoint(x: 32, y: y + 11), in: context)
            drawText(
                book.title,
                font: .systemFont(ofSize: 20, weight: .bold),
                color: Palette.ink,
                rect: CGRect(x: 52, y: y, width: 210, height: 25),
                alignment: .left
            )
            drawText(
                book.author ?? "未知作者",
                font: .systemFont(ofSize: 15, weight: .medium),
                color: Palette.muted,
                rect: CGRect(x: 270, y: y + 2, width: 108, height: 22),
                alignment: .right
            )
        }
    }

    private static func drawNotes(snapshot: WeReadPreviewSnapshot, in context: CGContext) {
        let rect = CGRect(x: Layout.margin, y: 420, width: 170, height: 96)
        drawRoundedRect(rect, fill: UIColor(red: 0.99, green: 0.96, blue: 0.86, alpha: 1), stroke: Palette.ink, in: context)
        drawText("笔记划线", font: .systemFont(ofSize: 15, weight: .bold), color: Palette.muted, rect: CGRect(x: 38, y: 436, width: 136, height: 22), alignment: .left)
        drawText("\(snapshot.totalNoteCount)", font: .systemFont(ofSize: 39, weight: .heavy), color: Palette.ink, rect: CGRect(x: 38, y: 460, width: 90, height: 44), alignment: .left)
        drawText("条", font: .systemFont(ofSize: 19, weight: .bold), color: Palette.orange, rect: CGRect(x: 124, y: 477, width: 38, height: 24), alignment: .left)

        let topTitle = snapshot.topNotebook?.book.title ?? "暂无笔记书籍"
        drawText(topTitle, font: .systemFont(ofSize: 14, weight: .semibold), color: Palette.muted, rect: CGRect(x: 206, y: 432, width: 172, height: 62), alignment: .right)
    }

    private static func drawRecommendations(_ books: [WeReadRecommendedBook], in _: CGContext) {
        let title = books.first?.title ?? "等待推荐"
        let author = books.first?.author ?? "微信读书"
        drawText("推荐下一本", font: .systemFont(ofSize: 15, weight: .bold), color: Palette.muted, rect: CGRect(x: Layout.margin, y: 536, width: 110, height: 22), alignment: .left)
        drawText("\(title) · \(author)", font: .systemFont(ofSize: 18, weight: .bold), color: Palette.ink, rect: CGRect(x: 126, y: 532, width: 252, height: 48), alignment: .right)
    }

    private static func drawDailyQuote(snapshot: WeReadPreviewSnapshot, in context: CGContext) {
        drawHeader(title: "书摘", updatedAt: snapshot.updatedAt, in: context)
        let bookmark = snapshot.dailyBookmark
        let quote = bookmark?.text ?? snapshot.recentBooks.first.map { "正在读《\($0.title)》，今天也给自己留一点安静的阅读时间。" } ?? "保存 Key 后读取划线，土豆片会每天展示一句书摘。"
        let bookTitle = bookmark?.bookTitle ?? snapshot.recentBooks.first?.title ?? "微信读书"
        let author = bookmark?.author ?? snapshot.recentBooks.first?.author ?? "每日划线"

        drawCornerMarks(in: context)
        drawFittedWrappedText(
            quote,
            maxFontSize: 32,
            minFontSize: 20,
            weight: .regular,
            color: Palette.ink,
            rect: CGRect(x: 68, y: 148, width: 266, height: 236),
            alignment: .left,
            lineSpacing: 7,
            verticallyCentered: false
        )
        drawLine(from: CGPoint(x: 36, y: 448), to: CGPoint(x: 364, y: 448), color: Palette.ink, width: 3, in: context)
        drawWrappedText(
            "— 《\(bookTitle)》 · \(author)",
            font: .systemFont(ofSize: 18, weight: .bold),
            color: Palette.ink,
            rect: CGRect(x: 42, y: 466, width: 316, height: 42),
            alignment: .left,
            lineSpacing: 3
        )
        drawText(
            bookmark?.chapterName ?? "来自你的微信读书划线",
            font: .systemFont(ofSize: 15, weight: .medium),
            color: Palette.muted,
            rect: CGRect(x: 42, y: 526, width: 316, height: 24),
            alignment: .left
        )
        drawText(
            "土豆片 · \(dateText(snapshot.updatedAt))",
            font: .systemFont(ofSize: 14, weight: .medium),
            color: Palette.muted,
            rect: CGRect(x: 42, y: 554, width: 316, height: 22),
            alignment: .left
        )
    }

    private static func drawBookshelf(snapshot: WeReadPreviewSnapshot, in context: CGContext) {
        drawHeader(title: "最近书架", updatedAt: snapshot.updatedAt, in: context)
        drawText("\(snapshot.shelfTotalCount)", font: .systemFont(ofSize: 92, weight: .heavy), color: Palette.ink, rect: CGRect(x: 22, y: 110, width: 150, height: 100), alignment: .left)
        drawText("本在书架", font: .systemFont(ofSize: 24, weight: .bold), color: Palette.green, rect: CGRect(x: 176, y: 156, width: 170, height: 34), alignment: .left)
        drawSectionTitle("最近打开", y: 236)
        for (index, book) in snapshot.recentBooks.prefix(5).enumerated() {
            let y = 276 + CGFloat(index) * 52
            drawText(String(format: "%02d", index + 1), font: .monospacedDigitSystemFont(ofSize: 20, weight: .bold), color: index == 0 ? Palette.green : Palette.muted, rect: CGRect(x: 24, y: y, width: 38, height: 26), alignment: .left)
            drawWrappedText(book.title, font: .systemFont(ofSize: 20, weight: .bold), color: Palette.ink, rect: CGRect(x: 70, y: y - 2, width: 220, height: 30), alignment: .left, lineSpacing: 0)
            drawText(book.author ?? "未知作者", font: .systemFont(ofSize: 14, weight: .medium), color: Palette.muted, rect: CGRect(x: 292, y: y + 2, width: 84, height: 22), alignment: .right)
        }
    }

    private static func drawNoteDigest(snapshot: WeReadPreviewSnapshot, in context: CGContext) {
        drawHeader(title: "笔记摘要", updatedAt: snapshot.updatedAt, in: context)
        drawRoundedRect(CGRect(x: 22, y: 112, width: 356, height: 144), fill: UIColor(red: 0.99, green: 0.96, blue: 0.86, alpha: 1), stroke: Palette.ink, in: context)
        drawText("\(snapshot.totalNoteCount)", font: .systemFont(ofSize: 76, weight: .heavy), color: Palette.ink, rect: CGRect(x: 48, y: 138, width: 150, height: 82), alignment: .left)
        drawText("条笔记划线\n覆盖 \(snapshot.notebookBookCount) 本书", font: .systemFont(ofSize: 22, weight: .bold), color: Palette.orange, rect: CGRect(x: 190, y: 150, width: 150, height: 70), alignment: .right)
        drawSectionTitle("笔记最多", y: 292)
        let topBook = snapshot.topNotebook
        drawWrappedText(topBook?.book.title ?? "暂无笔记书籍", font: .systemFont(ofSize: 32, weight: .heavy), color: Palette.ink, rect: CGRect(x: 30, y: 336, width: 340, height: 96), alignment: .center, lineSpacing: 5)
        drawText(topBook?.book.author ?? "微信读书", font: .systemFont(ofSize: 19, weight: .semibold), color: Palette.muted, rect: CGRect(x: 30, y: 448, width: 340, height: 28), alignment: .center)
        drawText("摘录、想法、书评都会汇总到这里", font: .systemFont(ofSize: 16, weight: .medium), color: Palette.muted, rect: CGRect(x: 30, y: 520, width: 340, height: 24), alignment: .center)
    }

    private static func drawRecommendationCard(snapshot: WeReadPreviewSnapshot, in context: CGContext) {
        drawHeader(title: "推荐下一本", updatedAt: snapshot.updatedAt, in: context)
        let book = snapshot.recommendedBooks.first
        drawText("NEXT", font: .systemFont(ofSize: 28, weight: .heavy), color: Palette.green, rect: CGRect(x: 28, y: 120, width: 120, height: 38), alignment: .left)
        drawWrappedText(book?.title ?? "等待推荐", font: .systemFont(ofSize: 42, weight: .heavy), color: Palette.ink, rect: CGRect(x: 30, y: 186, width: 340, height: 144), alignment: .center, lineSpacing: 8)
        drawText(book?.author ?? "微信读书", font: .systemFont(ofSize: 21, weight: .bold), color: Palette.muted, rect: CGRect(x: 30, y: 348, width: 340, height: 30), alignment: .center)
        drawWrappedText(book?.reason ?? book?.intro ?? "根据你的阅读偏好，为土豆片挑一本下一本书。", font: .systemFont(ofSize: 19, weight: .medium), color: Palette.muted, rect: CGRect(x: 42, y: 422, width: 316, height: 86), alignment: .center, lineSpacing: 4)
        drawLine(from: CGPoint(x: 82, y: 532), to: CGPoint(x: 318, y: 532), color: Palette.ink, width: 2, in: context)
    }

    private static func drawSectionTitle(_ title: String, y: CGFloat) {
        drawText(title, font: .systemFont(ofSize: 18, weight: .heavy), color: Palette.ink, rect: CGRect(x: Layout.margin, y: y, width: 160, height: 25), alignment: .left)
    }

    private static func drawText(_ text: String, font: UIFont, color: UIColor, rect: CGRect, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.lineSpacing = 2
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private static func drawWrappedText(_ text: String, font: UIFont, color: UIColor, rect: CGRect, alignment: NSTextAlignment, lineSpacing: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.lineSpacing = lineSpacing
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private static func drawFittedWrappedText(
        _ text: String,
        maxFontSize: CGFloat,
        minFontSize: CGFloat,
        weight: UIFont.Weight,
        color: UIColor,
        rect: CGRect,
        alignment: NSTextAlignment,
        lineSpacing: CGFloat,
        verticallyCentered: Bool
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.lineSpacing = lineSpacing

        var chosenFont = UIFont.systemFont(ofSize: minFontSize, weight: weight)
        var measuredHeight = rect.height
        var size = maxFontSize
        while size >= minFontSize {
            let font = UIFont.systemFont(ofSize: size, weight: weight)
            let bounds = textBoundingSize(text, font: font, paragraph: paragraph, width: rect.width)
            if bounds.height <= rect.height {
                chosenFont = font
                measuredHeight = bounds.height
                break
            }
            size -= 1
        }

        let yOffset = verticallyCentered ? max(0, (rect.height - measuredHeight) / 2) : 0
        (text as NSString).draw(
            in: rect.offsetBy(dx: 0, dy: yOffset),
            withAttributes: [
                .font: chosenFont,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private static func textBoundingSize(_ text: String, font: UIFont, paragraph: NSParagraphStyle, width: CGFloat) -> CGSize {
        (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ],
            context: nil
        ).integral.size
    }

    private static func drawCornerMarks(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(UIColor(red: 0.72, green: 0.16, blue: 0.12, alpha: 1).cgColor)
        context.setLineWidth(7)
        context.move(to: CGPoint(x: 54, y: 132))
        context.addLine(to: CGPoint(x: 54, y: 184))
        context.move(to: CGPoint(x: 54, y: 132))
        context.addLine(to: CGPoint(x: 88, y: 132))
        context.move(to: CGPoint(x: 346, y: 374))
        context.addLine(to: CGPoint(x: 346, y: 420))
        context.move(to: CGPoint(x: 312, y: 420))
        context.addLine(to: CGPoint(x: 346, y: 420))
        context.strokePath()
        context.restoreGState()
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    private static func drawLine(from: CGPoint, to: CGPoint, color: UIColor, width: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawDot(color: UIColor, center: CGPoint, in context: CGContext) {
        context.saveGState()
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
        context.restoreGState()
    }

    private static func drawRoundedRect(_ rect: CGRect, fill: UIColor, stroke: UIColor, in context: CGContext) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 16)
        context.saveGState()
        context.setFillColor(fill.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        context.addPath(path.cgPath)
        context.setStrokeColor(stroke.cgColor)
        context.setLineWidth(2)
        context.strokePath()
        context.restoreGState()
    }
}

struct WeReadSkillSetupView: View {
    @StateObject private var store = WeReadSkillSetupStore()
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsTokenPage = false
    @State private var confirmsKeyDeletion = false
    @State private var isShowingTransferPreview = false
    @State private var selectedTemplate: WeReadPreviewTemplate = .dailyQuote
    @State private var showsConnectionSettings = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if store.hasSavedKey {
                    previewSection
                    dataSection
                    connectionSummarySection
                } else {
                    headerCard
                    quickStartCard
                    keySection
                    capabilitySection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, AppBottomBarMetrics.scrollContentBottomPadding)
        }
        .background(pageBackgroundColor.ignoresSafeArea())
        .dismissKeyboardOnBackgroundTap()
        .navigationTitle("微信读书")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsTokenPage) {
            WeReadTokenPageView(url: store.tokenPageURL)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingTransferPreview) {
            TransferSheetView(
                sourceImage: previewImage,
                title: selectedTemplate.title
            ) {
                store.toastMessage = "已传输到土豆片"
            }
        }
        .alert("清空本机保存的微信读书 Key？", isPresented: $confirmsKeyDeletion) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                store.clearSavedKey()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .weReadAPIKeyDidChange)) { _ in
            store.reloadSavedKey()
        }
        .task {
            guard store.hasSavedKey, store.previewSnapshot == nil, !store.isLoadingPreviewData else { return }
            await store.refreshPreviewData()
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toastMessage {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .padding(.bottom, AppBottomBarMetrics.floatingControlBottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.2)) {
                                store.toastMessage = nil
                            }
                        }
                    }
            }
        }
    }

    private var previewImage: UIImage {
        if let snapshot = store.previewSnapshot {
            return WeReadSkillRenderer.render(snapshot: snapshot, template: selectedTemplate)
        }
        return WeReadSkillRenderer.renderPlaceholder(template: selectedTemplate)
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 14) {
            WeReadOfficialIcon(size: 54, cornerRadius: 16)

            VStack(alignment: .leading, spacing: 6) {
                Text("微信读书")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryTextColor)
                Text("一键跳转官方领 Key 页面，回到 App 粘贴保存，客户端直接读取微信读书开放数据。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(cardStroke)
    }

    private var quickStartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("快速接入")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(primaryTextColor)

            VStack(alignment: .leading, spacing: 10) {
                quickStartRow(index: 1, title: "打开官方领 Key 页面", detail: "微信读书登录同一账号后生成 wrk- 开头的个人 Key。")
                quickStartRow(index: 2, title: "复制 Key 回到 App", detail: "支持整段文本粘贴，App 会自动提取 wrk- token。")
                quickStartRow(index: 3, title: "保存并校验连接", detail: "Key 会保存到本机 Keychain，校验通过后即可接技能。")
            }

            HStack(spacing: 10) {
                Button {
                    showsTokenPage = true
                } label: {
                    Label("打开领 Key 页面", systemImage: "link")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    store.copyTokenPageLink()
                } label: {
                    Label("复制链接", systemImage: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 118, height: 42)
                        .background(rowFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke)
    }

    private var keySection: some View {
        keyManagementContent
            .padding(18)
            .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(cardStroke)
    }

    private var keyManagementContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("个人 Key")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(primaryTextColor)
                    Text(store.hasSavedKey ? "当前已保存：\(store.savedKeyPreview)" : "当前状态：等待填写")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer()

                Button("清空") {
                    confirmsKeyDeletion = true
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                .disabled(!store.hasSavedKey && store.apiKeyInput.trimmed.isEmpty)
            }

            HStack(spacing: 8) {
                Group {
                    if store.isKeyVisible {
                        TextField("输入或粘贴 wrk- 开头的 Key", text: $store.apiKeyInput)
                    } else {
                        SecureField("输入或粘贴 wrk- 开头的 Key", text: $store.apiKeyInput)
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(primaryTextColor)

                Button {
                    store.isKeyVisible.toggle()
                } label: {
                    Image(systemName: store.isKeyVisible ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 46)
            .background(rowFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    store.pasteAndSaveFromClipboard()
                } label: {
                    Label("一键粘贴并保存", systemImage: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(rowFillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    store.saveCurrentKey()
                } label: {
                    Label("保存 Key", systemImage: "tray.and.arrow.down.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 118, height: 40)
                        .background(rowFillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                Task {
                    await store.verifyCurrentKey()
                }
            } label: {
                HStack(spacing: 8) {
                    if store.isVerifying {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    }
                    Text(store.isVerifying ? "校验中…" : "校验连接")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(store.isVerifying ? 0.8 : 1)
            }
            .buttonStyle(.plain)
            .disabled(store.isVerifying)

            statusBanner
        }
    }

    private var statusBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusIconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(statusColor)
                .frame(width: 20, height: 20)

            Text(store.statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(primaryTextColor)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(statusColor.opacity(colorScheme == .dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("土豆片预览")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(primaryTextColor)
                    Text(store.previewSnapshot == nil ? "读取后会按土豆片尺寸生成多种预览图。" : "切换模板后，可直接预览并传输当前样式。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer()

                if store.isLoadingPreviewData {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            templatePicker

            deviceFramedPreview
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .background(rowFillColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    if selectedTemplate == .dailyQuote, store.previewSnapshot?.dailyBookmark != nil {
                        store.showNextDailyBookmark()
                    } else {
                        Task {
                            await store.refreshPreviewData()
                        }
                    }
                } label: {
                    Label(previewRefreshButtonTitle, systemImage: previewRefreshButtonIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(rowFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(store.isLoadingPreviewData)

                Button {
                    isShowingTransferPreview = true
                } label: {
                    Label("预览并传输", systemImage: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(store.isLoadingPreviewData)
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke)
    }

    private var previewRefreshButtonTitle: String {
        if store.isLoadingPreviewData {
            return "读取中..."
        }
        if selectedTemplate == .dailyQuote, store.previewSnapshot?.dailyBookmark != nil {
            return "换一句"
        }
        return "读取数据"
    }

    private var previewRefreshButtonIcon: String {
        if selectedTemplate == .dailyQuote, store.previewSnapshot?.dailyBookmark != nil {
            return "shuffle"
        }
        return "arrow.clockwise"
    }

    private var deviceFramedPreview: some View {
        ZStack {
            Image("ink_tatoo2")
                .resizable()
                .scaledToFit()
                .frame(width: 252, height: 336)
                .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
                .allowsHitTesting(false)

            Image(uiImage: previewImage)
                .resizable()
                .interpolation(.none)
                .scaledToFill()
                .frame(width: 180, height: 269)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .offset(y: -24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var templatePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WeReadPreviewTemplate.allCases) { template in
                    Button {
                        selectedTemplate = template
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: template.iconName)
                                .font(.system(size: 13, weight: .semibold))
                            Text(template.title)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(selectedTemplate == template ? .white : primaryTextColor)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            selectedTemplate == template ? accentColor : rowFillColor,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("读取到的数据")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(primaryTextColor)

            VStack(spacing: 10) {
                ForEach(dataRows) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: row.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .frame(width: 22, height: 22)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(secondaryTextColor)
                            Text(row.value)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(primaryTextColor)
                            if let detail = row.detail {
                                Text(detail)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(secondaryTextColor)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(rowFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke)
    }

    private var connectionSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.10, green: 0.65, blue: 0.36))
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("微信读书已接入")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(primaryTextColor)
                    Text("Key：\(store.savedKeyPreview)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsConnectionSettings.toggle()
                    }
                } label: {
                    Label(showsConnectionSettings ? "收起" : "管理", systemImage: showsConnectionSettings ? "chevron.up" : "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(rowFillColor, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if showsConnectionSettings {
                keyManagementContent
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
    }

    private var capabilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("接入后可读取")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(primaryTextColor)

            VStack(spacing: 10) {
                capabilityRow(icon: "books.vertical.fill", title: "书架", detail: "电子书、有声书、文章收藏入口、私密状态、最近阅读时间")
                capabilityRow(icon: "magnifyingglass", title: "搜索与详情", detail: "书名、作者、评分、简介、目录、阅读进度")
                capabilityRow(icon: "clock.arrow.circlepath", title: "阅读统计", detail: "周月年总时长、阅读天数、偏好分类、作者、出版社")
                capabilityRow(icon: "highlighter", title: "笔记与划线", detail: "有笔记的书、划线原文、个人想法、热门划线")
                capabilityRow(icon: "text.quote", title: "书评", detail: "推荐、最新、一般、差评等公开点评")
                capabilityRow(icon: "sparkles.rectangle.stack", title: "推荐", detail: "为你推荐、相似书推荐")
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke)
    }

    private func quickStartRow(index: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func capabilityRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(rowFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dataRows: [WeReadDataRow] {
        guard let snapshot = store.previewSnapshot else {
            return [
                WeReadDataRow(icon: "books.vertical.fill", title: "书架", value: "等待读取", detail: "点击“读取数据”后显示微信读书返回内容。"),
                WeReadDataRow(icon: "clock.arrow.circlepath", title: "阅读统计", value: "等待读取", detail: nil),
                WeReadDataRow(icon: "highlighter", title: "笔记", value: "等待读取", detail: nil)
            ]
        }

        return [
            WeReadDataRow(
                icon: "quote.bubble.fill",
                title: "每日划线",
                value: snapshot.dailyBookmark?.bookTitle ?? "暂未读取到",
                detail: snapshot.dailyBookmark?.text
            ),
            WeReadDataRow(
                icon: "books.vertical.fill",
                title: "书架",
                value: "\(snapshot.shelfTotalCount) 本",
                detail: snapshot.recentBookLine
            ),
            WeReadDataRow(
                icon: "clock.arrow.circlepath",
                title: "本月阅读",
                value: minutesText(snapshot.monthlyReadMinutes),
                detail: "\(snapshot.readDaysText) · 日均 \(minutesText(snapshot.dayAverageReadMinutes ?? 0))"
            ),
            WeReadDataRow(
                icon: "highlighter",
                title: "笔记划线",
                value: "\(snapshot.totalNoteCount) 条",
                detail: "覆盖 \(snapshot.notebookBookCount) 本书"
            ),
            WeReadDataRow(
                icon: "sparkles.rectangle.stack",
                title: "推荐",
                value: "\(snapshot.recommendedBooks.count) 本",
                detail: snapshot.recommendedBooks.first.map { "\($0.title) · \($0.author ?? "未知作者")" }
            )
        ]
    }

    private func minutesText(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) 分钟" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
    }

    private var statusIconName: String {
        switch store.statusTone {
        case .neutral:
            return "info.circle.fill"
        case .success:
            return "checkmark.seal.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch store.statusTone {
        case .neutral:
            return accentColor
        case .success:
            return Color(red: 0.10, green: 0.65, blue: 0.36)
        case .warning:
            return Color(red: 0.94, green: 0.52, blue: 0.17)
        }
    }

    private var pageBackgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(red: 0.98, green: 0.98, blue: 0.98)
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : .white
    }

    private var rowFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045)
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(cardStrokeColor, lineWidth: 1)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.52)
    }

    private var accentColor: Color {
        Color(red: 0.18, green: 0.49, blue: 0.98)
    }
}

private struct WeReadTokenPageView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(Color(red: 0.18, green: 0.49, blue: 0.98))
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
