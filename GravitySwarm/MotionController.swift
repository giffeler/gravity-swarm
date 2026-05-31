import CoreGraphics
import CoreMotion
import Foundation
import OSLog

final class MotionController: ObservableObject {
    private let logger = Logger(subsystem: "com.giffeler.gravityswarm", category: "Motion")
    private let motionManager = CMMotionManager()
    private var fallbackTimer: Timer?
    private var neutralTilt = CGVector(dx: 0, dy: 0)
    private var smoothedTilt = CGVector(dx: 0, dy: 0)
    private var calibrationAccumulator = CGVector(dx: 0, dy: 0)
    private var calibrationSamplesRemaining = 0

    private(set) var isUsingFallback = true

    var controlVector: CGVector {
        deadZoned(clamped(smoothedTilt, maxMagnitude: PerformanceConfig.maxTiltMagnitude))
    }

    func start() {
        stopFallbackTimer()
        beginCalibration()

        #if targetEnvironment(simulator)
        startFallbackTimer(animated: true)
        logger.info("Using simulator fallback motion")
        return
        #else
        guard motionManager.isDeviceMotionAvailable else {
            startFallbackTimer(animated: false)
            logger.warning("Device motion unavailable; using static fallback")
            return
        }

        isUsingFallback = false
        motionManager.deviceMotionUpdateInterval = PerformanceConfig.fixedTimeStep
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            self.ingestTilt(x: gravity.x, y: gravity.y)
        }
        logger.info("Started device motion updates")
        #endif
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        stopFallbackTimer()
        logger.info("Stopped motion updates")
    }

    func recalibrate() {
        beginCalibration()
        logger.info("Motion recalibration requested")
    }

    private func ingestTilt(x: Double, y: Double) {
        let mapped = CGVector(dx: CGFloat(x), dy: CGFloat(y))
        updateCalibrationIfNeeded(with: mapped)
        let calibrated = CGVector(
            dx: mapped.dx - neutralTilt.dx,
            dy: mapped.dy - neutralTilt.dy
        )
        smoothedTilt = lowPass(previous: smoothedTilt, next: calibrated)
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
            self.ingestTilt(x: Double(vector.dx), y: Double(vector.dy))
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

    private func beginCalibration() {
        calibrationSamplesRemaining = PerformanceConfig.calibrationSampleCount
        calibrationAccumulator = .zero
    }

    private func updateCalibrationIfNeeded(with tilt: CGVector) {
        guard calibrationSamplesRemaining > 0 else { return }

        calibrationAccumulator.dx += tilt.dx
        calibrationAccumulator.dy += tilt.dy
        calibrationSamplesRemaining -= 1

        guard calibrationSamplesRemaining == 0 else { return }

        let divisor = CGFloat(PerformanceConfig.calibrationSampleCount)
        neutralTilt = CGVector(
            dx: calibrationAccumulator.dx / divisor,
            dy: calibrationAccumulator.dy / divisor
        )
        smoothedTilt = .zero
        logger.info("Calibrated neutral tilt x=\(self.neutralTilt.dx, privacy: .public) y=\(self.neutralTilt.dy, privacy: .public)")
    }

    private func clamped(_ vector: CGVector, maxMagnitude: CGFloat) -> CGVector {
        let magnitude = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
        guard magnitude > maxMagnitude, magnitude > 0 else { return vector }
        let scale = maxMagnitude / magnitude
        return CGVector(dx: vector.dx * scale, dy: vector.dy * scale)
    }

    private func deadZoned(_ vector: CGVector) -> CGVector {
        let magnitude = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
        guard magnitude >= PerformanceConfig.tiltDeadZone else { return .zero }
        return vector
    }
}
