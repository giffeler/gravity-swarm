import SwiftUI

@main
struct GravitySwarmApp: App {
    var body: some Scene {
        WindowGroup {
            SwarmView()
                .persistentSystemOverlays(.hidden)
        }
    }
}
