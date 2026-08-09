import CoreGraphics
import Testing
@testable import GravitySwarm

struct SwarmSystemTests {
    private let size = CGSize(width: 205, height: 251)

    @Test
    func activeSwarmCountIsClamped() {
        let system = SwarmSystem()

        system.setActiveSwarmCount(PerformanceConfig.minimumSwarmCount - 1)
        #expect(system.activeSwarmCount == PerformanceConfig.minimumSwarmCount)

        system.setActiveSwarmCount(PerformanceConfig.maximumSwarmCount + 1)
        #expect(system.activeSwarmCount == PerformanceConfig.maximumSwarmCount)
    }

    @Test
    func fishRemainBoundedAndSpeedsRemainLimitedAfterLongRun() {
        let system = SwarmSystem()
        let boundary = RoundedDisplayBoundary(size: size)
        system.reset(in: size)
        system.setActiveSwarmCount(PerformanceConfig.maximumSwarmCount)

        for step in 0..<1_000 {
            let phase = CGFloat(step) * 0.071
            let control = CGVector(
                dx: cos(phase) * PerformanceConfig.maxTiltMagnitude,
                dy: sin(phase * 0.73) * PerformanceConfig.maxTiltMagnitude
            )
            system.update(
                bounds: size,
                control: control,
                timeStep: CGFloat(PerformanceConfig.fixedTimeStep)
            )
        }

        #expect(
            boundary.signedDistance(
                from: system.leader.position,
                radius: PerformanceConfig.leaderRadius
            ) <= 0.001
        )
        #expect(
            magnitude(system.leader.velocity)
                <= PerformanceConfig.leaderMaxSpeed + 0.001
        )

        for fish in system.swarm.prefix(system.activeSwarmCount) {
            #expect(
                boundary.signedDistance(
                    from: fish.position,
                    radius: PerformanceConfig.swarmRadius
                ) <= 0.001
            )
            #expect(
                magnitude(fish.velocity)
                    <= PerformanceConfig.swarmMaxSpeed + 0.001
            )
        }
    }

    @Test
    func movingFollowersKeepPhaseShiftedInternalMotion() {
        let system = SwarmSystem()
        let position = CGPoint(x: 80, y: 120)
        let target = CGPoint(x: 130, y: 120)
        let first = system.movingFollowAcceleration(
            for: Fish(position: position, velocity: .zero, wanderPhase: 0),
            index: 0,
            from: position,
            to: target
        )
        let second = system.movingFollowAcceleration(
            for: Fish(position: position, velocity: .zero, wanderPhase: .pi * 0.5),
            index: 0,
            from: position,
            to: target
        )

        #expect(first.dx > 0)
        #expect(second.dx > 0)
        #expect(abs(first.dy - second.dy) > 10)
    }

    private func magnitude(_ vector: CGVector) -> CGFloat {
        sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
    }
}
