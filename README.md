# Gravity Swarm

Gravity Swarm is a native watchOS prototype for Apple Watch Ultra. The app runs as a normal watchOS app and does not use private APIs or attempt to install a custom watch face.

## Requirements

- Xcode 26.4 or newer
- watchOS 26.4 or newer simulator or paired Apple Watch
- Swift / SwiftUI / SpriteKit / Core Motion

The deployment target is watchOS 26.4.

## Concept

The user steers one leader point, the "fish", by tilting the watch. The leader remains inside the visible rounded Apple Watch display. A swarm of smaller fish follows the leader while it moves. When the leader is idle, the swarm switches to loose wandering motion.

The Digital Crown controls the active swarm size. Fish nodes are pooled so changing the count does not create or destroy SpriteKit nodes during normal animation. On physical hardware, the current wrist angle is calibrated as neutral when motion starts. Double-tap the screen to recalibrate during a test run.

## Architecture

- `GravitySwarmApp.swift`: watchOS app entry point.
- `SwarmView.swift`: SwiftUI host for `SpriteView`, lifecycle handling, screen sizing, and Digital Crown input.
- `MotionController.swift`: Core Motion input with simulator fallback.
- `SwarmScene.swift`: SpriteKit scene, fixed timestep loop, node pooling, and rendering.
- `SwarmSystem.swift`: leader movement, rounded display boundary, and swarm behavior.
- `PerformanceConfig.swift`: frame rate, fish count, motion, and steering constants.

## Build

Open `GravitySwarm.xcodeproj` in Xcode, select the `GravitySwarm` scheme, then choose a watchOS simulator or paired Apple Watch destination.

From Terminal:

```sh
xcodebuild -project GravitySwarm.xcodeproj -scheme GravitySwarm -destination 'generic/platform=watchOS Simulator' -derivedDataPath /tmp/gravityswarm-dd build
```

The explicit `/tmp` DerivedData path avoids signing and extended-attribute issues when this repository lives in a synced Documents folder.

For physical-device signing, keep local signing values out of git:

```sh
cp Signing.example.xcconfig Signing.local.xcconfig
$EDITOR Signing.local.xcconfig
xcodebuild -project GravitySwarm.xcodeproj -scheme GravitySwarm -destination 'generic/platform=watchOS' -xcconfig Signing.local.xcconfig build
```

For the connected watch named `Vader`, command-line builds can use:

```sh
xcodebuild -project GravitySwarm.xcodeproj -scheme GravitySwarm -destination 'platform=watchOS,name=Vader' -derivedDataPath /tmp/gravityswarm-dd -xcconfig Signing.local.xcconfig build
```

`Signing.local.xcconfig` is ignored by git. Do not commit a real Apple Developer Team ID.

## Performance Notes

The app targets 30 fps with a fixed simulation timestep. The implementation avoids SpriteKit physics bodies and updates lightweight Swift structs instead. SpriteKit nodes and textures are created once and reused.

Initial limits are conservative for Apple Watch battery and thermal behavior. Real motion feel and battery impact should be validated on physical Apple Watch Ultra hardware before increasing the maximum swarm size. Runtime logs use the `com.giffeler.gravityswarm` subsystem for motion source, calibration, screen size, and Crown changes.

## Simulator

The simulator does not provide live Apple Watch motion input. Simulator builds use an animated fallback vector so the leader and swarm remain testable.
