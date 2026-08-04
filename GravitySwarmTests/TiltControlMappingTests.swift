import CoreGraphics
import Testing
@testable import GravitySwarm

struct TiltControlMappingTests {
    @Test
    func valuesInsideDeadZoneMapToZero() {
        let result = TiltControlMapping.remap(
            CGVector(dx: PerformanceConfig.tiltDeadZone * 0.5, dy: 0),
            deadZone: PerformanceConfig.tiltDeadZone,
            maximumMagnitude: PerformanceConfig.maxTiltMagnitude
        )

        #expect(result == .zero)
    }

    @Test
    func magnitudeIsRemappedContinuouslyAboveDeadZone() {
        let midpoint =
            (PerformanceConfig.tiltDeadZone + PerformanceConfig.maxTiltMagnitude)
            * 0.5
        let result = TiltControlMapping.remap(
            CGVector(dx: midpoint, dy: 0),
            deadZone: PerformanceConfig.tiltDeadZone,
            maximumMagnitude: PerformanceConfig.maxTiltMagnitude
        )

        #expect(abs(result.dx - 0.5) < 0.0001)
        #expect(abs(result.dy) < 0.0001)
    }

    @Test
    func valuesAboveMaximumAreClampedAndKeepDirection() {
        let result = TiltControlMapping.remap(
            CGVector(dx: 3, dy: 4),
            deadZone: PerformanceConfig.tiltDeadZone,
            maximumMagnitude: PerformanceConfig.maxTiltMagnitude
        )

        #expect(abs(result.dx - 0.6) < 0.0001)
        #expect(abs(result.dy - 0.8) < 0.0001)
    }
}
