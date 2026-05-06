import ActivityKit
import Foundation
import OSLog

@MainActor
final class LiveTransferActivityController {
    private var activity: Activity<TransferActivityAttributes>?
    private let logger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "LiveTransferActivity")

    var isActive: Bool {
        activity != nil || !Activity<TransferActivityAttributes>.activities.isEmpty
    }

    @discardableResult
    func start(deviceName: String) -> Bool {
        startOrUpdate(deviceName: deviceName, progress: 0, phaseTitle: "准备传输")
    }

    @discardableResult
    func startOrUpdate(deviceName: String, progress: Double, phaseTitle: String) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.error("Live Activity not started because system authorization is disabled.")
            return false
        }

        if activity == nil, let existingActivity = Activity<TransferActivityAttributes>.activities.first {
            activity = existingActivity
        }

        if activity != nil {
            update(progress: progress, phaseTitle: phaseTitle)
            logger.info("Live Activity already exists, update progress for \(deviceName, privacy: .public).")
            return true
        }

        let attributes = TransferActivityAttributes(deviceName: deviceName)
        let state = TransferActivityAttributes.ContentState(progress: progress, phaseTitle: phaseTitle)

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            logger.info("Live Activity requested for \(deviceName, privacy: .public).")
            return true
        } catch {
            logger.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
            activity = nil
            return false
        }
    }

    func update(progress: Double, phaseTitle: String) {
        if activity == nil, let existingActivity = Activity<TransferActivityAttributes>.activities.first {
            activity = existingActivity
        }

        guard let activity else {
            logger.notice("Live Activity update skipped because no activity exists. phase=\(phaseTitle, privacy: .public), progress=\(progress, privacy: .public)")
            return
        }
        let state = TransferActivityAttributes.ContentState(progress: progress, phaseTitle: phaseTitle)

        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end(progress: Double, phaseTitle: String, immediate: Bool = false) {
        let activities = Activity<TransferActivityAttributes>.activities
        guard let activity = activity ?? activities.first else {
            logger.notice("Live Activity end skipped because no activity exists. phase=\(phaseTitle, privacy: .public)")
            return
        }
        // 先清空引用，避免结束中的旧活动继续收到后续进度更新。
        self.activity = nil

        let state = TransferActivityAttributes.ContentState(progress: progress, phaseTitle: phaseTitle)
        let dismissalPolicy: ActivityUIDismissalPolicy = immediate
            ? .immediate
            : .after(Date().addingTimeInterval(8))
        let activitiesToEnd = [activity] + activities.filter { $0.id != activity.id }

        Task { [activitiesToEnd] in
            for activity in activitiesToEnd {
                await activity.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: dismissalPolicy
                )
            }
        }
    }
}
