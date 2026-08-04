import CoreGraphics
import Foundation

struct Fish {
    var position: CGPoint
    var velocity: CGVector
    var wanderPhase: CGFloat
}

struct RoundedDisplayBoundary {
    private struct InsetShape {
        let radius: CGFloat
        let straightHalfWidth: CGFloat
        let straightHalfHeight: CGFloat
    }

    let size: CGSize
    let cornerRadius: CGFloat
    let edgeInset: CGFloat
    private let leaderShape: InsetShape
    private let swarmShape: InsetShape

    init(size: CGSize) {
        let cornerRadius =
            min(size.width, size.height) * PerformanceConfig.displayCornerRadiusRatio
        self.size = size
        self.cornerRadius = cornerRadius
        self.edgeInset = PerformanceConfig.displayEdgeInset
        self.leaderShape = Self.makeInsetShape(
            size: size,
            cornerRadius: cornerRadius,
            edgeInset: PerformanceConfig.displayEdgeInset,
            fishRadius: PerformanceConfig.leaderRadius
        )
        self.swarmShape = Self.makeInsetShape(
            size: size,
            cornerRadius: cornerRadius,
            edgeInset: PerformanceConfig.displayEdgeInset,
            fishRadius: PerformanceConfig.swarmRadius
        )
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
        let boundary = signedDistanceAndNormal(from: position, radius: radius)
        guard boundary.signedDistance > 0 else { return }

        position.x -= boundary.normal.dx * (boundary.signedDistance + 0.25)
        position.y -= boundary.normal.dy * (boundary.signedDistance + 0.25)

        let velocityOutward =
            velocity.dx * boundary.normal.dx + velocity.dy * boundary.normal.dy
        if velocityOutward > 0 {
            velocity.dx -= velocityOutward * boundary.normal.dx
            velocity.dy -= velocityOutward * boundary.normal.dy
        }
    }

    func edgeInfluence(point: CGPoint, radius: CGFloat, threshold: CGFloat) -> (normal: CGVector, strength: CGFloat)? {
        let boundary = signedDistanceAndNormal(from: point, radius: radius)
        guard boundary.signedDistance >= -threshold else { return nil }
        let strength = min(
            max((threshold + boundary.signedDistance) / threshold, 0),
            1
        )
        return (boundary.normal, strength)
    }

    func signedDistance(from point: CGPoint, radius: CGFloat) -> CGFloat {
        signedDistanceAndNormal(from: point, radius: radius).signedDistance
    }

    func signedDistanceAndNormal(
        from point: CGPoint,
        radius: CGFloat
    ) -> (signedDistance: CGFloat, normal: CGVector) {
        let shape = insetShape(for: radius)
        let localX = point.x - size.width * 0.5
        let localY = point.y - size.height * 0.5
        let qX = abs(localX) - shape.straightHalfWidth
        let qY = abs(localY) - shape.straightHalfHeight
        let outsideX = max(qX, 0)
        let outsideY = max(qY, 0)
        let outsideDistance = sqrt(outsideX * outsideX + outsideY * outsideY)
        let signedDistance =
            outsideDistance + min(max(qX, qY), 0) - shape.radius
        let normal: CGVector

        if outsideDistance > 0.0001 {
            normal = CGVector(
                dx: sign(localX) * outsideX / outsideDistance,
                dy: sign(localY) * outsideY / outsideDistance
            )
        } else if qX > qY {
            normal = CGVector(dx: sign(localX), dy: 0)
        } else {
            normal = CGVector(dx: 0, dy: sign(localY))
        }

        return (signedDistance, normal)
    }

    private func insetShape(for radius: CGFloat) -> InsetShape {
        if radius == PerformanceConfig.leaderRadius {
            return leaderShape
        }
        if radius == PerformanceConfig.swarmRadius {
            return swarmShape
        }

        return Self.makeInsetShape(
            size: size,
            cornerRadius: cornerRadius,
            edgeInset: edgeInset,
            fishRadius: radius
        )
    }

    private static func makeInsetShape(
        size: CGSize,
        cornerRadius: CGFloat,
        edgeInset: CGFloat,
        fishRadius: CGFloat
    ) -> InsetShape {
        let margin = edgeInset + fishRadius
        let halfWidth = max(0, size.width * 0.5 - margin)
        let halfHeight = max(0, size.height * 0.5 - margin)
        let radius = min(max(0, cornerRadius - margin), halfWidth, halfHeight)
        return InsetShape(
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
    private var smoothedLeaderAcceleration = CGVector.zero
    private var positionSnapshot = [CGPoint](
        repeating: .zero,
        count: PerformanceConfig.maximumSwarmCount
    )
    private var separationAccelerations = [CGVector](
        repeating: .zero,
        count: PerformanceConfig.maximumSwarmCount
    )
    private var gridHeads: [Int] = []
    private var gridNext = [Int](
        repeating: -1,
        count: PerformanceConfig.maximumSwarmCount
    )
    private var gridColumnCount = 1
    private var gridRowCount = 1
    private var cachedBoundary: RoundedDisplayBoundary?

    func reset(in bounds: CGSize) {
        let boundary = RoundedDisplayBoundary(size: bounds)
        cachedBoundary = boundary
        configureGrid(for: bounds)
        leader = Fish(
            position: CGPoint(x: bounds.width * 0.5, y: bounds.height * 0.5),
            velocity: .zero,
            wanderPhase: 0
        )
        smoothedLeaderAcceleration = .zero

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

        let boundary = boundary(for: bounds)
        updateLeader(control: control, boundary: boundary, timeStep: timeStep)
        updateSwarm(boundary: boundary, timeStep: timeStep)
    }

    private func updateLeader(control: CGVector, boundary: RoundedDisplayBoundary, timeStep: CGFloat) {
        var leaderFish = leader
        var acceleration = CGVector(
            dx: control.dx * PerformanceConfig.leaderAcceleration,
            dy: control.dy * PerformanceConfig.leaderAcceleration
        )
        var shouldApplyAccelerationImmediately = false

        if let edge = boundary.edgeInfluence(
            point: leaderFish.position,
            radius: PerformanceConfig.leaderRadius,
            threshold: PerformanceConfig.leaderBoundarySoftZone
        ) {
            shouldApplyAccelerationImmediately = true
            let accelerationOutward = dot(acceleration, edge.normal)
            if accelerationOutward > 0 {
                acceleration.dx -= edge.normal.dx * accelerationOutward * edge.strength
                acceleration.dy -= edge.normal.dy * accelerationOutward * edge.strength
            }

            let smoothedOutward = dot(smoothedLeaderAcceleration, edge.normal)
            if smoothedOutward > 0 {
                smoothedLeaderAcceleration.dx -= edge.normal.dx * smoothedOutward
                smoothedLeaderAcceleration.dy -= edge.normal.dy * smoothedOutward
            }

            let currentOutward = dot(leaderFish.velocity, edge.normal)
            if currentOutward > 0 {
                let damping = PerformanceConfig.leaderBoundaryOutwardVelocityDamping * edge.strength
                leaderFish.velocity.dx -= edge.normal.dx * currentOutward * damping
                leaderFish.velocity.dy -= edge.normal.dy * currentOutward * damping
            }
        }

        if shouldApplyAccelerationImmediately {
            smoothedLeaderAcceleration = acceleration
        } else {
            smoothedLeaderAcceleration = CGVector(
                dx: smoothedLeaderAcceleration.dx + (acceleration.dx - smoothedLeaderAcceleration.dx) * PerformanceConfig.leaderAccelerationSmoothing,
                dy: smoothedLeaderAcceleration.dy + (acceleration.dy - smoothedLeaderAcceleration.dy) * PerformanceConfig.leaderAccelerationSmoothing
            )
        }
        leaderFish.velocity.dx += smoothedLeaderAcceleration.dx * timeStep
        leaderFish.velocity.dy += smoothedLeaderAcceleration.dy * timeStep
        leaderFish.velocity = limited(leaderFish.velocity, maxSpeed: PerformanceConfig.leaderMaxSpeed)
        leaderFish.velocity.dx *= PerformanceConfig.leaderVelocityDamping
        leaderFish.velocity.dy *= PerformanceConfig.leaderVelocityDamping

        leaderFish.position.x += leaderFish.velocity.dx * timeStep
        leaderFish.position.y += leaderFish.velocity.dy * timeStep
        boundary.resolve(
            position: &leaderFish.position,
            velocity: &leaderFish.velocity,
            radius: PerformanceConfig.leaderRadius
        )
        leader = leaderFish
    }

    private func updateSwarm(boundary: RoundedDisplayBoundary, timeStep: CGFloat) {
        let count = min(activeSwarmCount, swarm.count)
        guard count > 0 else { return }

        let leaderMoving = speed(leader.velocity) > PerformanceConfig.movingSpeedThreshold
        let target = leader.position

        for index in 0..<count {
            positionSnapshot[index] = swarm[index].position
        }
        rebuildSeparationAccelerations(count: count)

        for index in 0..<count {
            var fish = swarm[index]
            var acceleration = leaderMoving
                ? followAcceleration(from: positionSnapshot[index], to: target)
                : wanderAcceleration(for: fish, index: index)

            let separation = separationAccelerations[index]
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

    private func rebuildSeparationAccelerations(count: Int) {
        let desired = PerformanceConfig.desiredSpacing
        let desiredSquared = desired * desired
        let columnCount = gridColumnCount
        let rowCount = gridRowCount

        positionSnapshot.withUnsafeBufferPointer { positions in
            gridHeads.withUnsafeMutableBufferPointer { heads in
                gridNext.withUnsafeMutableBufferPointer { nextIndices in
                    separationAccelerations.withUnsafeMutableBufferPointer { accelerations in
                        for cellIndex in heads.indices {
                            heads[cellIndex] = -1
                        }
                        for index in 0..<count {
                            accelerations[index] = .zero
                            let position = positions[index]
                            let column = min(
                                max(Int(position.x / desired), 0),
                                columnCount - 1
                            )
                            let row = min(
                                max(Int(position.y / desired), 0),
                                rowCount - 1
                            )
                            let cellIndex = row * columnCount + column
                            nextIndices[index] = heads[cellIndex]
                            heads[cellIndex] = index
                        }

                        for index in 0..<count {
                            let position = positions[index]
                            let column = min(
                                max(Int(position.x / desired), 0),
                                columnCount - 1
                            )
                            let row = min(
                                max(Int(position.y / desired), 0),
                                rowCount - 1
                            )
                            let minimumColumn = max(column - 1, 0)
                            let maximumColumn = min(column + 1, columnCount - 1)
                            let minimumRow = max(row - 1, 0)
                            let maximumRow = min(row + 1, rowCount - 1)

                            for neighborRow in minimumRow...maximumRow {
                                for neighborColumn in minimumColumn...maximumColumn {
                                    var otherIndex =
                                        heads[neighborRow * columnCount + neighborColumn]
                                    while otherIndex >= 0 {
                                        if otherIndex > index {
                                            let other = positions[otherIndex]
                                            let dx = position.x - other.x
                                            let dy = position.y - other.y
                                            let distanceSquared = dx * dx + dy * dy

                                            if distanceSquared > 0.01,
                                               distanceSquared < desiredSquared {
                                                let distance = sqrt(distanceSquared)
                                                let strength =
                                                    (desired - distance) / desired
                                                    * PerformanceConfig.separationAcceleration
                                                let force = CGVector(
                                                    dx: dx / distance * strength,
                                                    dy: dy / distance * strength
                                                )
                                                accelerations[index].dx += force.dx
                                                accelerations[index].dy += force.dy
                                                accelerations[otherIndex].dx -= force.dx
                                                accelerations[otherIndex].dy -= force.dy
                                            }
                                        }
                                        otherIndex = nextIndices[otherIndex]
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func boundary(for bounds: CGSize) -> RoundedDisplayBoundary {
        if let cachedBoundary, cachedBoundary.size == bounds {
            return cachedBoundary
        }

        let boundary = RoundedDisplayBoundary(size: bounds)
        cachedBoundary = boundary
        configureGrid(for: bounds)
        return boundary
    }

    private func configureGrid(for bounds: CGSize) {
        gridColumnCount = max(
            Int(ceil(bounds.width / PerformanceConfig.desiredSpacing)),
            1
        )
        gridRowCount = max(
            Int(ceil(bounds.height / PerformanceConfig.desiredSpacing)),
            1
        )
        let cellCount = gridColumnCount * gridRowCount
        if gridHeads.count != cellCount {
            gridHeads = [Int](repeating: -1, count: cellCount)
        }
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

    private func dot(_ first: CGVector, _ second: CGVector) -> CGFloat {
        first.dx * second.dx + first.dy * second.dy
    }

    private func speed(_ vector: CGVector) -> CGFloat {
        length(vector)
    }
}
