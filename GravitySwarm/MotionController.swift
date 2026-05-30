import CoreGraphics
import CoreMotion
import Foundation

final class MotionController: ObservableObject {
    private let motionManager = CMMotionManager()
    private var fallbackTimer: Timer?
    private var smoothedTilt = CGVector(dx: 0, dy: 0)

    private(set) var isUsingFallback = true

    var controlVector: CGVector {
        clamped(smoothedTilt, maxMagnitude: PerformanceConfig.maxTiltMagnitude)
    }

    func start() {
        stopFallbackTimer()

        #if targetEnvironment(simulator)
        startFallbackTimer(animated: true)
        return
        #else
        guard motionManager.isDeviceMotionAvailable else {
            startFallbackTimer(animated: false)
            return
        }

        isUsingFallback = false
        motionManager.deviceMotionUpdateInterval = PerformanceConfig.fixedTimeStep
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            self.ingestTilt(x: gravity.x, y: gravity.y)
        }
        #endif
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        stopFallbackTimer()
    }

    private func ingestTilt(x: Double, y: Double) {
        let mapped = CGVector(dx: CGFloat(x), dy: CGFloat(y))
        smoothedTilt = lowPass(previous: smoothedTilt, next: mapped)
    }

    private func startFallbackTimer(animated: Bool) {
        isUsingFallback = true
        guard animated else {
            smoothedTilt = CGVector(dx: 0, dy: 0)
            return
        }

        let startDate = Date()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: PerformanceConfig.fixedTimeStep, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(startDate)
            let angle = CGFloat(elapsed * 0.75)
            let vector = CGVector(dx: cos(angle) * 0.75, dy: sin(angle * 0.8) * 0.65)
            self.smoothedTilt = self.lowPass(previous: self.smoothedTilt, next: vector)
        }
    }

    private func stopFallbackTimer() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func lowPass(previous: CGVector, next: CGVector) -> CGVector {
        CGVector(
            dx: previous.dx + (next.dx - previous.dx) * PerformanceConfig.motionSmoothing,
            dy: previous.dy + (next.dy - previous.dy) * PerformanceConfig.motionSmoothing
        )
    }

    private func clamped(_ vector: CGVector, maxMagnitude: CGFloat) -> CGVector {
        let magnitude = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
        guard magnitude > maxMagnitude, magnitude > 0 else { return vector }
        let scale = maxMagnitude / magnitude
        return CGVector(dx: vector.dx * scale, dy: vector.dy * scale)
    }
}
