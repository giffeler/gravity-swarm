import CoreGraphics
import Foundation

struct Fish {
    var position: CGPoint
    var velocity: CGVector
    var wanderPhase: CGFloat
}

struct RoundedDisplayBoundary {
    let size: CGSize
    let cornerRadius: CGFloat
    let edgeInset: CGFloat

    init(size: CGSize) {
        self.size = size
        self.cornerRadius = min(size.width, size.height) * PerformanceConfig.displayCornerRadiusRatio
        self.edgeInset = PerformanceConfig.displayEdgeInset
    }

    func randomPoint(radius: CGFloat) -> CGPoint {
        let margin = edgeInset + radius
        let minX = margin
        let maxX = max(minX, size.width - margin)
        let minY = margin
        let maxY = max(minY, size.height - margin)

        for _ in 0..<24 {
            let point = CGPoint(
                x: CGFloat.random(in: minX...maxX),
                y: CGFloat.random(in: minY...maxY)
            )
            if signedDistance(from: point, radius: radius) <= 0 {
                return point
            }
        }

        return CGPoint(x: size.width * 0.5, y: size.height * 0.5)
    }

    func resolve(position: inout CGPoint, velocity: inout CGVector, radius: CGFloat) {
        let distance = signedDistance(from: position, radius: radius)
        guard distance > 0 else { return }

        let normal = outwardNormal(at: position, radius: radius)
        position.x -= normal.dx * (distance + 0.25)
        position.y -= normal.dy * (distance + 0.25)

        let velocityOutward = velocity.dx * normal.dx + velocity.dy * normal.dy
        if velocityOutward > 0 {
            velocity.dx -= velocityOutward * normal.dx
            velocity.dy -= velocityOutward * normal.dy
        }
    }

    private func signedDistance(from point: CGPoint, radius: CGFloat) -> CGFloat {
        let shape = insetShape(for: radius)
        let localX = point.x - size.width * 0.5
        let localY = point.y - size.height * 0.5
        let qX = abs(localX) - shape.straightHalfWidth
        let qY = abs(localY) - shape.straightHalfHeight
        let outsideX = max(qX, 0)
        let outsideY = max(qY, 0)
        let outsideDistance = sqrt(outsideX * outsideX + outsideY * outsideY)
        return outsideDistance + min(max(qX, qY), 0) - shape.radius
    }

    private func outwardNormal(at point: CGPoint, radius: CGFloat) -> CGVector {
        let shape = insetShape(for: radius)
        let localX = point.x - size.width * 0.5
        let localY = point.y - size.height * 0.5
        let qX = abs(localX) - shape.straightHalfWidth
        let qY = abs(localY) - shape.straightHalfHeight
        let outsideX = max(qX, 0)
        let outsideY = max(qY, 0)
        let outsideLength = sqrt(outsideX * outsideX + outsideY * outsideY)

        if outsideLength > 0.0001 {
            return CGVector(
                dx: sign(localX) * outsideX / outsideLength,
                dy: sign(localY) * outsideY / outsideLength
            )
        }

        if qX > qY {
            return CGVector(dx: sign(localX), dy: 0)
        }

        return CGVector(dx: 0, dy: sign(localY))
    }

    private func insetShape(for radius: CGFloat) -> (radius: CGFloat, straightHalfWidth: CGFloat, straightHalfHeight: CGFloat) {
        let margin = edgeInset + radius
        let halfWidth = max(0, size.width * 0.5 - margin)
        let halfHeight = max(0, size.height * 0.5 - margin)
        let radius = min(max(0, cornerRadius - margin), halfWidth, halfHeight)
        return (
            radius: radius,
            straightHalfWidth: max(0, halfWidth - radius),
            straightHalfHeight: max(0, halfHeight - radius)
        )
    }

    private func sign(_ value: CGFloat) -> CGFloat {
        value < 0 ? -1 : 1
    }
}

final class SwarmSystem {
    private(set) var leader = Fish(position: .zero, velocity: .zero, wanderPhase: 0)
    private(set) var swarm: [Fish] = []
    private(set) var activeSwarmCount = PerformanceConfig.defaultSwarmCount

    func reset(in bounds: CGSize) {
        let boundary = RoundedDisplayBoundary(size: bounds)
        leader = Fish(
            position: CGPoint(x: bounds.width * 0.5, y: bounds.height * 0.5),
            velocity: .zero,
            wanderPhase: 0
        )

        swarm.removeAll(keepingCapacity: true)
        swarm.reserveCapacity(PerformanceConfig.maximumSwarmCount)
        for index in 0..<PerformanceConfig.maximumSwarmCount {
            swarm.append(
                Fish(
                    position: boundary.randomPoint(radius: PerformanceConfig.swarmRadius),
                    velocity: CGVector(dx: CGFloat.random(in: -12...12), dy: CGFloat.random(in: -12...12)),
                    wanderPhase: CGFloat(index) * 0.37
                )
            )
        }
    }

    func setActiveSwarmCount(_ count: Int) {
        activeSwarmCount = max(
            PerformanceConfig.minimumSwarmCount,
            min(count, PerformanceConfig.maximumSwarmCount)
        )
    }

    func update(bounds: CGSize, control: CGVector, timeStep: CGFloat) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        if swarm.isEmpty {
            reset(in: bounds)
        }

        let boundary = RoundedDisplayBoundary(size: bounds)
        updateLeader(control: control, boundary: boundary, timeStep: timeStep)
        updateSwarm(boundary: boundary, timeStep: timeStep)
    }

    private func updateLeader(control: CGVector, boundary: RoundedDisplayBoundary, timeStep: CGFloat) {
        leader.velocity.dx += control.dx * PerformanceConfig.leaderAcceleration * timeStep
        leader.velocity.dy += control.dy * PerformanceConfig.leaderAcceleration * timeStep
        leader.velocity = limited(leader.velocity, maxSpeed: PerformanceConfig.leaderMaxSpeed)
        leader.velocity.dx *= PerformanceConfig.leaderVelocityDamping
        leader.velocity.dy *= PerformanceConfig.leaderVelocityDamping

        leader.position.x += leader.velocity.dx * timeStep
        leader.position.y += leader.velocity.dy * timeStep
        boundary.resolve(
            position: &leader.position,
            velocity: &leader.velocity,
            radius: PerformanceConfig.leaderRadius
        )
    }

    private func updateSwarm(boundary: RoundedDisplayBoundary, timeStep: CGFloat) {
        let count = min(activeSwarmCount, swarm.count)
        guard count > 0 else { return }

        let leaderMoving = speed(leader.velocity) > PerformanceConfig.movingSpeedThreshold
        let target = leader.position

        for index in 0..<count {
            var fish = swarm[index]
            var acceleration = leaderMoving
                ? followAcceleration(from: fish.position, to: target)
                : wanderAcceleration(for: fish, index: index)

            let separation = separationAcceleration(for: fish.position, index: index, count: count)
            acceleration.dx += separation.dx
            acceleration.dy += separation.dy

            if leaderMoving {
                acceleration.dx += (leader.velocity.dx - fish.velocity.dx) * PerformanceConfig.alignmentFactor
                acceleration.dy += (leader.velocity.dy - fish.velocity.dy) * PerformanceConfig.alignmentFactor
            }

            fish.velocity.dx += acceleration.dx * timeStep
            fish.velocity.dy += acceleration.dy * timeStep
            fish.velocity = limited(fish.velocity, maxSpeed: PerformanceConfig.swarmMaxSpeed)
            fish.velocity.dx *= PerformanceConfig.swarmVelocityDamping
            fish.velocity.dy *= PerformanceConfig.swarmVelocityDamping
            fish.position.x += fish.velocity.dx * timeStep
            fish.position.y += fish.velocity.dy * timeStep
            fish.wanderPhase += timeStep

            boundary.resolve(
                position: &fish.position,
                velocity: &fish.velocity,
                radius: PerformanceConfig.swarmRadius
            )

            swarm[index] = fish
        }
    }

    private func followAcceleration(from position: CGPoint, to target: CGPoint) -> CGVector {
        let offset = CGVector(dx: target.x - position.x, dy: target.y - position.y)
        let distance = max(length(offset), 1)
        let scale = min(distance / 48.0, 1.0) * PerformanceConfig.followAcceleration / distance
        return CGVector(dx: offset.dx * scale, dy: offset.dy * scale)
    }

    private func wanderAcceleration(for fish: Fish, index: Int) -> CGVector {
        let angle = fish.wanderPhase * 1.7 + CGFloat(index) * 0.61
        return CGVector(
            dx: cos(angle) * PerformanceConfig.wanderAcceleration,
            dy: sin(angle * 0.83) * PerformanceConfig.wanderAcceleration
        )
    }

    private func separationAcceleration(for position: CGPoint, index: Int, count: Int) -> CGVector {
        let desired = PerformanceConfig.desiredSpacing
        let desiredSquared = desired * desired
        var result = CGVector.zero

        for otherIndex in 0..<count where otherIndex != index {
            let other = swarm[otherIndex].position
            let dx = position.x - other.x
            let dy = position.y - other.y
            let distanceSquared = dx * dx + dy * dy
            guard distanceSquared > 0.01, distanceSquared < desiredSquared else { continue }

            let distance = sqrt(distanceSquared)
            let strength = (desired - distance) / desired
            result.dx += (dx / distance) * strength * PerformanceConfig.separationAcceleration
            result.dy += (dy / distance) * strength * PerformanceConfig.separationAcceleration
        }

        return result
    }

    private func limited(_ vector: CGVector, maxSpeed: CGFloat) -> CGVector {
        let magnitude = length(vector)
        guard magnitude > maxSpeed, magnitude > 0 else { return vector }
        let scale = maxSpeed / magnitude
        return CGVector(dx: vector.dx * scale, dy: vector.dy * scale)
    }

    private func length(_ vector: CGVector) -> CGFloat {
        sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
    }

    private func speed(_ vector: CGVector) -> CGFloat {
        length(vector)
    }
}
