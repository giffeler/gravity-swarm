import CoreGraphics
import Foundation
import SpriteKit

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

    override init() {
        super.init(size: CGSize(width: 205, height: 251))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .black
        addChild(fishLayer)
        leaderNode.zPosition = 10
        addChild(leaderNode)
        swarmSystem.reset(in: size)
        swarmSystem.setActiveSwarmCount(desiredSwarmCount)
        ensureNodes()
        render()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        #if DEBUG
        view.showsFPS = PerformanceConfig.showsPerformanceMetrics
        view.showsNodeCount = PerformanceConfig.showsPerformanceMetrics
        view.showsDrawCount = PerformanceConfig.showsPerformanceMetrics
        #endif
    }

    func configure(size newSize: CGSize, motionController: MotionController) {
        self.motionController = motionController
        guard newSize.width > 1, newSize.height > 1 else { return }

        let roundedSize = CGSize(width: newSize.width.rounded(.down), height: newSize.height.rounded(.down))
        if size != roundedSize {
            size = roundedSize
            swarmSystem.reset(in: roundedSize)
            swarmSystem.setActiveSwarmCount(desiredSwarmCount)
        }

        ensureNodes()
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
        render()
    }

    override func update(_ currentTime: TimeInterval) {
        guard let previousUpdateTime else {
            self.previousUpdateTime = currentTime
            return
        }

        let frameDelta = min(currentTime - previousUpdateTime, PerformanceConfig.maxAccumulatedTime)
        self.previousUpdateTime = currentTime
        accumulator += frameDelta

        let control = motionController?.controlVector ?? .zero
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

        guard let swarmTexture else { return }
        while swarmNodes.count < PerformanceConfig.maximumSwarmCount {
            let node = SKSpriteNode(texture: swarmTexture)
            node.blendMode = .add
            node.zPosition = 2
            swarmNodes.append(node)
            fishLayer.addChild(node)
        }
    }

    private func render() {
        ensureNodes()

        let leader = swarmSystem.leader
        leaderNode.position = leader.position
        leaderNode.size = CGSize(
            width: PerformanceConfig.leaderRadius * 2.0,
            height: PerformanceConfig.leaderRadius * 2.0
        )
        leaderNode.zRotation = rotation(for: leader.velocity)

        let activeCount = min(swarmSystem.activeSwarmCount, swarmSystem.swarm.count, swarmNodes.count)
        for index in 0..<swarmNodes.count {
            let node = swarmNodes[index]
            guard index < activeCount else {
                node.isHidden = true
                continue
            }

            let fish = swarmSystem.swarm[index]
            node.isHidden = false
            node.position = fish.position
            node.size = CGSize(
                width: PerformanceConfig.swarmRadius * 2.0,
                height: PerformanceConfig.swarmRadius * 2.0
            )
            node.zRotation = rotation(for: fish.velocity)
            node.alpha = 0.72
        }
    }

    private func rotation(for velocity: CGVector) -> CGFloat {
        guard abs(velocity.dx) + abs(velocity.dy) > 0.001 else { return 0 }
        return atan2(velocity.dy, velocity.dx)
    }

    private static func makeFishTexture(diameter: Int, color: CGColor) -> SKTexture? {
        let bytesPerPixel = 4
        let bytesPerRow = diameter * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: diameter * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let image = rgba.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: diameter,
                height: diameter,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }

            let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            let radius = CGFloat(diameter) * 0.5
            context.clear(rect)
            context.translateBy(x: radius, y: radius)
            context.setFillColor(color)

            let body = CGRect(
                x: -radius * 0.45,
                y: -radius * 0.32,
                width: radius * 0.9,
                height: radius * 0.64
            )
            context.fillEllipse(in: body)

            context.beginPath()
            context.move(to: CGPoint(x: -radius * 0.38, y: 0))
            context.addLine(to: CGPoint(x: -radius * 0.82, y: radius * 0.34))
            context.addLine(to: CGPoint(x: -radius * 0.82, y: -radius * 0.34))
            context.closePath()
            context.fillPath()

            context.beginPath()
            context.move(to: CGPoint(x: radius * 0.36, y: 0))
            context.addLine(to: CGPoint(x: radius * 0.68, y: radius * 0.18))
            context.addLine(to: CGPoint(x: radius * 0.68, y: -radius * 0.18))
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
