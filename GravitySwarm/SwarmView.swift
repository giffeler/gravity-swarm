import SpriteKit
import SwiftUI
import WatchKit
import OSLog

struct SwarmView: View {
    private let logger = Logger(subsystem: "com.giffeler.gravityswarm", category: "SwarmView")

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motionController = MotionController()
    @State private var scene = SwarmScene()
    @State private var crownValue = Double(PerformanceConfig.defaultSwarmCount)
    @State private var isScenePaused = false

    var body: some View {
        GeometryReader { proxy in
            let renderSize = fullScreenSize(fallback: proxy.size)

            SpriteView(
                scene: scene,
                isPaused: isScenePaused,
                preferredFramesPerSecond: PerformanceConfig.preferredFramesPerSecond
            )
                .frame(width: renderSize.width, height: renderSize.height)
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
                .background(Color.black)
                .focusable(true)
                .onTapGesture(count: 2) {
                    motionController.recalibrate()
                    WKInterfaceDevice.current().play(.click)
                }
                .digitalCrownRotation(
                    $crownValue,
                    from: Double(PerformanceConfig.minimumSwarmCount),
                    through: Double(PerformanceConfig.maximumSwarmCount),
                    by: PerformanceConfig.crownStep,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                .onAppear {
                    configureScene(size: renderSize)
                    isScenePaused = false
                    scene.setSimulationPaused(false)
                    motionController.start()
                    logger.info("App appeared with render size \(renderSize.width, privacy: .public)x\(renderSize.height, privacy: .public)")
                }
                .onDisappear {
                    isScenePaused = true
                    scene.setSimulationPaused(true)
                    motionController.stop()
                }
                .onChange(of: crownValue) { _, newValue in
                    let count = Int(newValue.rounded())
                    scene.setDesiredSwarmCount(count)
                    logger.info("Swarm count set to \(count, privacy: .public)")
                }
                .onChange(of: proxy.size) { _, newSize in
                    configureScene(size: fullScreenSize(fallback: newSize))
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        configureScene(size: renderSize)
                        isScenePaused = false
                        scene.setSimulationPaused(false)
                        motionController.start()
                    default:
                        isScenePaused = true
                        scene.setSimulationPaused(true)
                        motionController.stop()
                    }
                }
        }
    }

    private func configureScene(size: CGSize) {
        scene.configure(size: size, motionController: motionController)
        scene.setDesiredSwarmCount(Int(crownValue.rounded()))
    }

    private func fullScreenSize(fallback: CGSize) -> CGSize {
        let screen = WKInterfaceDevice.current().screenBounds.size
        return CGSize(
            width: max(fallback.width, screen.width),
            height: max(fallback.height, screen.height)
        )
    }
}

#Preview {
    SwarmView()
}
