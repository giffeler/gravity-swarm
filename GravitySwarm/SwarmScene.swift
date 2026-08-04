import CoreGraphics
import Foundation
import OSLog
import SpriteKit
import WatchKit

@MainActor
final class SwarmScene: SKScene {
    private let swarmSystem = SwarmSystem()
    private let fishLayer = SKNode()
    private let leaderNode = SKSpriteNode()

    private weak var motionController: MotionController?
    private var swarmNodes: [SKSpriteNode] = []
    private var leaderTexture: SKTexture?
    private var swarmTexture: SKTexture?
    private var accumulator: TimeInterval = 0
    private var previousUpdateTime: TimeInterval?
    private var desiredSwarmCount = PerformanceConfig.defaultSwarmCount
    private var previousActiveCount = 0
    private var isConfigured = false
    private var configuredSize = CGSize.zero
    private var requestedFramesPerSecond = PerformanceConfig.preferredFramesPerSecond
    private var frameRateHandler: ((Int) -> Void)?
    #if DEBUG
    private let performanceLogger = Logger(
        subsystem: "com.giffeler.gravityswarm",
        category: "Performance"
    )
    private var performanceFrameCount = 0
    private var accumulatedUpdateDuration: TimeInterval = 0
    private var accumulatedFrameDuration: TimeInterval = 0
    private var previousPerformanceFrameTime: TimeInterval?
    #endif

    override init() {
        super.init(size: CGSize(width: 1, height: 1))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .black
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        motionController: MotionController,
        frameRateHandler: @escaping (Int) -> Void
    ) {
        self.motionController = motionController
        self.frameRateHandler = frameRateHandler
        configureSimulationIfNeeded(for: size)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        configureSimulationIfNeeded(for: size)
    }

    private func configureSimulationIfNeeded(for newSize: CGSize) {
        guard newSize.width > 1, newSize.height > 1 else { return }
        if !isConfigured || configuredSize != newSize {
            configuredSize = newSize
            swarmSystem.reset(in: newSize)
            swarmSystem.setActiveSwarmCount(desiredSwarmCount)
        }

        if !isConfigured {
            isConfigured = true
            addChild(fishLayer)
            leaderNode.zPosition = 10
            fishLayer.addChild(leaderNode)
            ensureNodes()
        }
        render()
    }

    func setSimulationPaused(_ paused: Bool) {
        if paused {
            previousUpdateTime = nil
            accumulator = 0
        }
    }

    func setDesiredSwarmCount(_ count: Int) {
        desiredSwarmCount = count
        swarmSystem.setActiveSwarmCount(count)
        if isConfigured {
            render()
        }
    }

    func setReduceMotionEnabled(_ enabled: Bool) {
        swarmSystem.setReduceMotionEnabled(enabled)
    }

    override func update(_ currentTime: TimeInterval) {
        #if DEBUG
        let updateStartTime = ProcessInfo.processInfo.systemUptime
        defer {
            recordPerformanceFrame(currentTime: currentTime, updateStartTime: updateStartTime)
        }
        #endif

        guard isConfigured else { return }
        guard let previousUpdateTime else {
            self.previousUpdateTime = currentTime
            return
        }

        let frameDelta = min(currentTime - previousUpdateTime, PerformanceConfig.maxAccumulatedTime)
        self.previousUpdateTime = currentTime
        accumulator += frameDelta

        let control = motionController?.controlVector ?? .zero
        updatePreferredFrameRate(control: control)
        while accumulator >= PerformanceConfig.fixedTimeStep {
            swarmSystem.update(
                bounds: size,
                control: control,
                timeStep: CGFloat(PerformanceConfig.fixedTimeStep)
            )
            accumulator -= PerformanceConfig.fixedTimeStep
        }

        render()
    }

    private func updatePreferredFrameRate(control: CGVector) {
        let controlMagnitudeSquared = control.dx * control.dx + control.dy * control.dy
        let threshold = PerformanceConfig.idleControlMagnitudeThreshold
        let leaderSpeedSquared =
            swarmSystem.leader.velocity.dx * swarmSystem.leader.velocity.dx
            + swarmSystem.leader.velocity.dy * swarmSystem.leader.velocity.dy
        let isIdle =
            controlMagnitudeSquared <= threshold * threshold
            && leaderSpeedSquared
                < PerformanceConfig.movingSpeedThreshold
                    * PerformanceConfig.movingSpeedThreshold
        let preferredFramesPerSecond = isIdle
            ? PerformanceConfig.idlePreferredFramesPerSecond
            : PerformanceConfig.preferredFramesPerSecond
        guard preferredFramesPerSecond != requestedFramesPerSecond else { return }

        requestedFramesPerSecond = preferredFramesPerSecond
        frameRateHandler?(preferredFramesPerSecond)
    }

    #if DEBUG
    private func recordPerformanceFrame(
        currentTime: TimeInterval,
        updateStartTime: TimeInterval
    ) {
        if let previousPerformanceFrameTime {
            accumulatedFrameDuration += currentTime - previousPerformanceFrameTime
        }
        self.previousPerformanceFrameTime = currentTime
        accumulatedUpdateDuration += ProcessInfo.processInfo.systemUptime - updateStartTime
        performanceFrameCount += 1

        guard performanceFrameCount >= PerformanceConfig.performanceMeasurementFrameCount else {
            return
        }

        let measuredIntervals = max(performanceFrameCount - 1, 1)
        let averageUpdateMilliseconds =
            accumulatedUpdateDuration / Double(performanceFrameCount) * 1_000
        let averageFrameMilliseconds =
            accumulatedFrameDuration / Double(measuredIntervals) * 1_000
        performanceLogger.notice(
            "PERF averageUpdateMs=\(averageUpdateMilliseconds, format: .fixed(precision: 3)) averageFrameMs=\(averageFrameMilliseconds, format: .fixed(precision: 3)) activeFish=\(self.swarmSystem.activeSwarmCount)"
        )

        performanceFrameCount = 0
        accumulatedUpdateDuration = 0
        accumulatedFrameDuration = 0
        previousPerformanceFrameTime = nil
    }
    #endif

    private func ensureNodes() {
        if leaderTexture == nil {
            leaderTexture = Self.makeFishTexture(
                diameter: 18,
                color: CGColor(red: 0.96, green: 0.98, blue: 0.78, alpha: 1.0)
            )
        }
        if swarmTexture == nil {
            swarmTexture = Self.makeFishTexture(
                diameter: 10,
                color: CGColor(red: 0.35, green: 0.9, blue: 1.0, alpha: 0.92)
            )
        }

        if let leaderTexture {
            leaderNode.texture = leaderTexture
        }
        let leaderSize = CGSize(
            width: PerformanceConfig.leaderRadius * 2.0,
            height: PerformanceConfig.leaderRadius * 2.0
        )
        if leaderNode.size != leaderSize {
            leaderNode.size = leaderSize
        }

        guard let swarmTexture else { return }
        while swarmNodes.count < PerformanceConfig.maximumSwarmCount {
            let node = SKSpriteNode(texture: swarmTexture)
            node.blendMode = .add
            node.zPosition = 2
            node.size = CGSize(
                width: PerformanceConfig.swarmRadius * 2.0,
                height: PerformanceConfig.swarmRadius * 2.0
            )
            node.alpha = 0.72
            node.isHidden = true
            swarmNodes.append(node)
            fishLayer.addChild(node)
        }
    }

    private func render() {
        let leader = swarmSystem.leader
        leaderNode.position = leader.position
        leaderNode.zRotation = rotation(for: leader.velocity)

        let activeCount = min(
            swarmSystem.activeSwarmCount,
            swarmSystem.swarm.count,
            swarmNodes.count
        )
        updateNodeVisibility(activeCount: activeCount)
        for index in 0..<activeCount {
            let node = swarmNodes[index]
            let fish = swarmSystem.swarm[index]
            node.position = fish.position
            node.zRotation = rotation(for: fish.velocity)
        }
    }

    private func updateNodeVisibility(activeCount: Int) {
        if activeCount > previousActiveCount {
            for index in previousActiveCount..<activeCount {
                swarmNodes[index].isHidden = false
            }
        } else if activeCount < previousActiveCount {
            for index in activeCount..<previousActiveCount {
                swarmNodes[index].isHidden = true
            }
        }
        previousActiveCount = activeCount
    }

    private func rotation(for velocity: CGVector) -> CGFloat {
        guard abs(velocity.dx) + abs(velocity.dy) > 0.001 else { return 0 }
        return atan2(velocity.dy, velocity.dx)
    }

    private static func makeFishTexture(diameter: CGFloat, color: CGColor) -> SKTexture? {
        let scale = WKInterfaceDevice.current().screenScale
        let pixelDiameter = max(Int(ceil(diameter * scale)), 1)
        let bytesPerPixel = 4
        let bytesPerRow = pixelDiameter * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: pixelDiameter * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let image = rgba.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: pixelDiameter,
                height: pixelDiameter,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }

            let rect = CGRect(
                x: 0,
                y: 0,
                width: pixelDiameter,
                height: pixelDiameter
            )
            context.clear(rect)
            context.scaleBy(x: scale, y: scale)
            let radius = diameter * 0.5
            context.translateBy(x: radius, y: radius)
            context.setFillColor(color)

            let body = CGRect(
                x: -radius * 0.55,
                y: -radius * 0.55,
                width: radius * 1.3,
                height: radius * 1.1
            )
            context.fillEllipse(in: body)

            context.beginPath()
            context.move(to: CGPoint(x: -radius * 0.4, y: 0))
            context.addLine(to: CGPoint(x: -radius * 0.95, y: radius * 0.65))
            context.addLine(to: CGPoint(x: -radius * 0.95, y: -radius * 0.65))
            context.closePath()
            context.fillPath()

            context.beginPath()
            context.move(to: CGPoint(x: radius * 0.62, y: 0))
            context.addLine(to: CGPoint(x: radius * 0.95, y: radius * 0.25))
            context.addLine(to: CGPoint(x: radius * 0.95, y: -radius * 0.25))
            context.closePath()
            context.fillPath()

            return context.makeImage()
        }

        guard let image else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        return texture
    }
}
