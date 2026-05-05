import ActivityKit
import Foundation
import OSLog

@MainActor
final class LiveTransferActivityController {
    private var activity: Activity<TransferActivityAttributes>?
    private let logger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "LiveTransferActivity")

    @discardableResult
    func start(deviceName: String) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.error("Live Activity not started because system authorization is disabled.")
            return false
        }

        if activity != nil {
            update(progress: 0, phaseTitle: "准备传输")
            logger.info("Live Activity already exists, reset progress for \(deviceName, privacy: .public).")
            return true
        }

        let attributes = TransferActivityAttributes(deviceName: deviceName)
        let state = TransferActivityAttributes.ContentState(progress: 0, phaseTitle: "准备传输")

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
        guard let activity else {
            logger.notice("Live Activity end skipped because no activity exists. phase=\(phaseTitle, privacy: .public)")
            return
        }
        let state = TransferActivityAttributes.ContentState(progress: progress, phaseTitle: phaseTitle)
        let dismissalPolicy: ActivityUIDismissalPolicy = immediate
            ? .immediate
            : .after(Date().addingTimeInterval(8))

        Task { [weak self, activity] in
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: dismissalPolicy
            )

            await MainActor.run {
                if self?.activity?.id == activity.id {
                    self?.activity = nil
                }
            }
        }
    }
}
