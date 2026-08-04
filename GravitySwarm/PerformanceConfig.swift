import CoreGraphics
import Foundation

enum PerformanceConfig {
    static let preferredFramesPerSecond = 30
    static let fixedTimeStep: TimeInterval = 1.0 / 60.0
    static let maxAccumulatedTime: TimeInterval = fixedTimeStep * 6.0

    static let defaultSwarmCount = 48
    static let minimumSwarmCount = 0
    static let maximumSwarmCount = 180
    static let crownStep = 1.0

    static let leaderRadius: CGFloat = 5.0
    static let swarmRadius: CGFloat = 2.4
    static let displayCornerRadiusRatio: CGFloat = 0.235
    static let displayEdgeInset: CGFloat = 2.0

    static let motionSmoothing: CGFloat = 0.14
    static let maxTiltMagnitude: CGFloat = 1.25
    static let tiltDeadZone: CGFloat = 0.035
    static let calibrationSampleCount = 12
    static let neutralTiltXDefaultsKey = "motion.neutralTilt.x"
    static let neutralTiltYDefaultsKey = "motion.neutralTilt.y"
    static let leaderAcceleration: CGFloat = 520.0
    static let leaderAccelerationSmoothing: CGFloat = 0.35
    static let leaderBoundarySoftZone: CGFloat = 18.0
    static let leaderBoundaryOutwardVelocityDamping: CGFloat = 0.75
    static let leaderVelocityDamping: CGFloat = 0.965
    static let leaderMaxSpeed: CGFloat = 135.0
    static let movingSpeedThreshold: CGFloat = 8.0

    static let followAcceleration: CGFloat = 95.0
    static let wanderAcceleration: CGFloat = 26.0
    static let separationAcceleration: CGFloat = 130.0
    static let alignmentFactor: CGFloat = 0.025
    static let swarmVelocityDamping: CGFloat = 0.982
    static let swarmMaxSpeed: CGFloat = 95.0
    static let desiredSpacing: CGFloat = 8.0
}
