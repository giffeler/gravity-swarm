import CoreGraphics
import CoreMotion
import Foundation
import OSLog
import WatchKit

final class MotionController: ObservableObject {
    private let logger = Logger(subsystem: "com.giffeler.gravityswarm", category: "Motion")
    private let motionManager = CMMotionManager()
    private let defaults: UserDefaults
    private var fallbackTimer: Timer?
    private var neutralTilt = CGVector(dx: 0, dy: 0)
    private var smoothedTilt = CGVector(dx: 0, dy: 0)
    private var calibrationAccumulator = CGVector(dx: 0, dy: 0)
    private var calibrationSamplesRemaining = 0
    private lazy var reversesMotionAxes: Bool = {
        let reversesAxes = WKInterfaceDevice.current().crownOrientation == .left
        let mode = reversesAxes ? "reversed" : "standard"
        logger.info("Crown orientation uses \(mode, privacy: .public) motion axes")
        return reversesAxes
    }()

    private(set) var isUsingFallback = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let neutralTilt = Self.loadNeutralTilt(from: defaults) {
            self.neutralTilt = neutralTilt
            logger.info("Loaded persisted neutral tilt")
        } else {
            beginCalibration()
        }
    }

    var controlVector: CGVector {
        deadZoned(clamped(smoothedTilt, maxMagnitude: PerformanceConfig.maxTiltMagnitude))
    }

    func start() {
        stopFallbackTimer()

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
        let axisDirection: CGFloat = reversesMotionAxes ? -1 : 1
        let mapped = CGVector(dx: CGFloat(x) * axisDirection, dy: CGFloat(y) * axisDirection)
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
        defaults.set(Double(neutralTilt.dx), forKey: PerformanceConfig.neutralTiltXDefaultsKey)
        defaults.set(Double(neutralTilt.dy), forKey: PerformanceConfig.neutralTiltYDefaultsKey)
        smoothedTilt = .zero
        logger.info("Calibrated neutral tilt x=\(self.neutralTilt.dx, privacy: .public) y=\(self.neutralTilt.dy, privacy: .public)")
    }

    private static func loadNeutralTilt(from defaults: UserDefaults) -> CGVector? {
        guard defaults.object(forKey: PerformanceConfig.neutralTiltXDefaultsKey) != nil,
              defaults.object(forKey: PerformanceConfig.neutralTiltYDefaultsKey) != nil else {
            return nil
        }

        return CGVector(
            dx: defaults.double(forKey: PerformanceConfig.neutralTiltXDefaultsKey),
            dy: defaults.double(forKey: PerformanceConfig.neutralTiltYDefaultsKey)
        )
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
