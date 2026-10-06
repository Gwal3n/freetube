import Foundation
import QuartzCore

/// Samples display-link callback spacing only while the player is being moved. A single summary
/// per gesture reaches the opt-in diagnostic log; no work or logging is added to SwiftUI bodies.
/// Callback gaps can reveal main-run-loop stalls, but are not a measurement of decoded video FPS.
@available(iOS 17.0, *)
@MainActor
final class PlayerTransitionFrameMonitor: NSObject {
    private struct Samples {
        var count = 0
        var over25ms = 0
        var over50ms = 0
        var maximumMilliseconds = 0.0

        mutating func record(_ seconds: CFTimeInterval) {
            let milliseconds = seconds * 1_000
            count += 1
            if milliseconds > 25 { over25ms += 1 }
            if milliseconds > 50 { over50ms += 1 }
            maximumMilliseconds = max(maximumMilliseconds, milliseconds)
        }
    }

    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlayerTransition")
    private var displayLink: CADisplayLink?
    private var finishTask: Task<Void, Never>?
    private var previousTimestamp: CFTimeInterval?
    private var label = ""
    private var outcome = ""
    private var isSettling = false
    private var dragSamples = Samples()
    private var settleSamples = Samples()

    var isActive: Bool { displayLink != nil }

    func begin(_ label: String) {
        stop()
        self.label = label
        outcome = "interrupted"
        isSettling = false
        previousTimestamp = nil
        dragSamples = Samples()
        settleSamples = Samples()

        let link = CADisplayLink(target: self, selector: #selector(sample(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func settle(_ outcome: String) {
        guard displayLink != nil else { return }
        self.outcome = outcome
        isSettling = true
        previousTimestamp = nil
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        finishTask?.cancel()
        finishTask = nil
        displayLink?.invalidate()
        displayLink = nil
        previousTimestamp = nil

        guard dragSamples.count + settleSamples.count > 0 else { return }
        log.info("\(label) \(outcome): drag callbacks=\(dragSamples.count) gaps>25ms=\(dragSamples.over25ms) gaps>50ms=\(dragSamples.over50ms) max=\(Int(dragSamples.maximumMilliseconds))ms; settle callbacks=\(settleSamples.count) gaps>25ms=\(settleSamples.over25ms) gaps>50ms=\(settleSamples.over50ms) max=\(Int(settleSamples.maximumMilliseconds))ms")
        dragSamples = Samples()
        settleSamples = Samples()
    }

    @objc private func sample(_ link: CADisplayLink) {
        if let previousTimestamp {
            let gap = link.timestamp - previousTimestamp
            if gap > 0 {
                if isSettling {
                    settleSamples.record(gap)
                } else {
                    dragSamples.record(gap)
                }
            }
        }
        previousTimestamp = link.timestamp
    }
}
