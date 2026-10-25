import Foundation

/// Opt-in scroll-cadence measurements for comparing the player panel with comments closed/open.
/// These are scroll geometry callback gaps, not presented-frame FPS.
@available(iOS 17.0, *)
@MainActor
final class PlayerScrollDiagnostics {
    static let shared = PlayerScrollDiagnostics()

    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlayerScroll")
    private var commentsExpanded = false
    private var isRecording = false
    private var lastSampleTime: TimeInterval?
    private var gaps: [TimeInterval] = []
    private var pauses = 0

    private init() {}

    func setCommentsExpanded(_ expanded: Bool) {
        guard commentsExpanded != expanded else { return }
        finish()
        commentsExpanded = expanded
    }

    func begin() {
        isRecording = true
        lastSampleTime = nil
        gaps.removeAll(keepingCapacity: true)
        pauses = 0
    }

    func record() {
        guard isRecording else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if let lastSampleTime {
            let gap = now - lastSampleTime
            if gap > 0, gap <= 0.2 {
                if gaps.count < 4_096 { gaps.append(gap) }
            } else if gap > 0.2 {
                // A held finger and a long stall look identical from scroll callbacks alone.
                pauses += 1
            }
        }
        self.lastSampleTime = now
    }

    func finish() {
        guard isRecording else { return }
        isRecording = false
        defer {
            gaps.removeAll(keepingCapacity: true)
            lastSampleTime = nil
            pauses = 0
        }
        guard gaps.count >= 8 else { return }

        let sorted = gaps.sorted()
        let median = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        let maxGap = sorted[sorted.count - 1]
        let over25ms = gaps.filter { $0 > 0.025 }.count
        let over50ms = gaps.filter { $0 > 0.050 }.count
        let comments = commentsExpanded ? "expanded" : "collapsed"
        log.info("Player scroll cadence: comments=\(comments), samples=\(gaps.count), median=\(milliseconds(median))ms, p95=\(milliseconds(p95))ms, max=\(milliseconds(maxGap))ms, gaps>25ms=\(over25ms), gaps>50ms=\(over50ms), pauses>200ms=\(pauses)")
    }

    private func milliseconds(_ interval: TimeInterval) -> Int {
        Int((interval * 1_000).rounded())
    }
}
