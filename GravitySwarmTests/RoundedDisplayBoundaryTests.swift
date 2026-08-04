import CoreGraphics
import Testing
@testable import GravitySwarm

struct RoundedDisplayBoundaryTests {
    private let size = CGSize(width: 205, height: 251)

    @Test
    func signedDistanceClassifiesInsideEdgeAndOutside() {
        let boundary = RoundedDisplayBoundary(size: size)
        let radius = PerformanceConfig.swarmRadius
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let rightEdge = CGPoint(
            x: size.width - PerformanceConfig.displayEdgeInset - radius,
            y: center.y
        )
        let outside = CGPoint(x: size.width, y: center.y)

        #expect(boundary.signedDistance(from: center, radius: radius) < 0)
        #expect(abs(boundary.signedDistance(from: rightEdge, radius: radius)) < 0.001)
        #expect(boundary.signedDistance(from: outside, radius: radius) > 0)
    }

    @Test
    func cornerNormalPointsOutward() {
        let boundary = RoundedDisplayBoundary(size: size)
        let sample = boundary.signedDistanceAndNormal(
            from: CGPoint(x: size.width, y: size.height),
            radius: PerformanceConfig.leaderRadius
        )
        let normalLength = sqrt(
            sample.normal.dx * sample.normal.dx
                + sample.normal.dy * sample.normal.dy
        )

        #expect(sample.signedDistance > 0)
        #expect(sample.normal.dx > 0)
        #expect(sample.normal.dy > 0)
        #expect(abs(normalLength - 1) < 0.001)
    }

    @Test
    func randomPointsAlwaysStayInside() {
        let boundary = RoundedDisplayBoundary(size: size)

        for radius in [PerformanceConfig.leaderRadius, PerformanceConfig.swarmRadius] {
            for _ in 0..<1_000 {
                let point = boundary.randomPoint(radius: radius)
                #expect(boundary.signedDistance(from: point, radius: radius) <= 0.001)
            }
        }
    }
}
