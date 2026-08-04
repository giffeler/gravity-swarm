import SpriteKit
import SwiftUI
import WatchKit
import OSLog

struct SwarmView: View {
    private let logger = Logger(subsystem: "com.giffeler.gravityswarm", category: "SwarmView")

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var motionController = MotionController()
    @State private var scene = SwarmScene()
    @State private var crownValue = Double(PerformanceConfig.defaultSwarmCount)
    @State private var isScenePaused = false
    @State private var preferredFramesPerSecond = PerformanceConfig.preferredFramesPerSecond
    @State private var hasAppliedAccessibilityDefault = false

    var body: some View {
        SpriteView(
            scene: scene,
            isPaused: isScenePaused,
            preferredFramesPerSecond: preferredFramesPerSecond
        )
            .ignoresSafeArea()
            .background(Color.black)
            .focusable(true)
            .onTapGesture(count: 2) {
                motionController.recalibrate()
                WKInterfaceDevice.current().play(.click)
            }
            .digitalCrownRotation(
                detent: $crownValue,
                from: Double(PerformanceConfig.minimumSwarmCount),
                through: Double(PerformanceConfig.maximumSwarmCount),
                by: PerformanceConfig.crownStep,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true,
                onIdle: {
                    let count = Int(crownValue.rounded())
                    logger.debug("Swarm count set to \(count, privacy: .public)")
                }
            )
            .onAppear {
                applyAccessibilityDefaultIfNeeded()
                configureScene()
                isScenePaused = false
                scene.setSimulationPaused(false)
                motionController.start()
                logger.info("App appeared")
            }
            .onDisappear {
                isScenePaused = true
                scene.setSimulationPaused(true)
                motionController.stop()
            }
            .onChange(of: crownValue) { _, newValue in
                scene.setDesiredSwarmCount(Int(newValue.rounded()))
            }
            .onChange(of: accessibilityReduceMotion) { _, enabled in
                scene.setReduceMotionEnabled(enabled)
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    configureScene()
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

    private func configureScene() {
        scene.configure(
            motionController: motionController,
            frameRateHandler: { preferredFramesPerSecond = $0 }
        )
        scene.setReduceMotionEnabled(accessibilityReduceMotion)
        scene.setDesiredSwarmCount(Int(crownValue.rounded()))
    }

    private func applyAccessibilityDefaultIfNeeded() {
        guard !hasAppliedAccessibilityDefault else { return }
        hasAppliedAccessibilityDefault = true
        if accessibilityReduceMotion {
            crownValue = Double(PerformanceConfig.reducedMotionDefaultSwarmCount)
        }
    }
}

#Preview {
    SwarmView()
}
