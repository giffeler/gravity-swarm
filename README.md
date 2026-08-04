# Gravity Swarm

Gravity Swarm is a native watchOS prototype for Apple Watch Ultra. The app runs as a normal watchOS app and does not use private APIs or attempt to install a custom watch face.

## Requirements

- Xcode 26.5 or newer
- watchOS 26.5 or newer simulator or paired Apple Watch
- Swift 6 / SwiftUI / SpriteKit / Core Motion

The deployment target is watchOS 26.5.

## Concept

The user steers one leader point, the "fish", by tilting the watch. The leader remains inside the visible rounded Apple Watch display. A swarm of smaller fish follows the leader while it moves. When the leader is idle, the swarm switches to loose wandering motion.

The Digital Crown controls the active swarm size. Fish nodes are pooled so changing the count does not create or destroy SpriteKit nodes during normal animation.

On the first app run, the current wrist angle is sampled as neutral and persisted. Later foreground activations and wrist raises reuse that value instead of recalibrating while the arm may still be moving. Double-tap the screen to explicitly recalibrate and replace the persisted neutral value. When the Digital Crown is worn on the left, both Core Motion axes are reversed to match the watchOS interface rotation.

## Architecture

- `GravitySwarmApp.swift`: watchOS app entry point.
- `SwarmView.swift`: SwiftUI host for `SpriteView`, lifecycle handling, accessibility, and Digital Crown input.
- `MotionController.swift`: Core Motion input with simulator fallback.
- `SwarmScene.swift`: SpriteKit scene, fixed timestep loop, deferred node pooling, rendering, and idle frame-rate selection.
- `SwarmSystem.swift`: leader movement, cached rounded display boundary, uniform-grid separation, and swarm behavior.
- `PerformanceConfig.swift`: frame rate, fish count, motion, and steering constants.
- `GravitySwarmTests`: Swift Testing coverage for boundary geometry, long-running swarm containment, speed limits, count clamping, and tilt remapping.

## Build

Open `GravitySwarm.xcodeproj` in Xcode, select the `GravitySwarm` scheme, then choose a watchOS simulator or paired Apple Watch destination.

From Terminal:

```sh
xcodebuild -project GravitySwarm.xcodeproj -scheme GravitySwarm -destination 'generic/platform=watchOS Simulator' -derivedDataPath /tmp/gravityswarm-dd build
```

The explicit `/tmp` DerivedData path avoids signing and extended-attribute issues when this repository lives in a synced Documents folder.

## Tests

Run the Swift Testing suite on an installed watchOS simulator:

```sh
xcodebuild -project GravitySwarm.xcodeproj -scheme GravitySwarm \
  -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' \
  -derivedDataPath /tmp/gravityswarm-dd test
```

The shared `GravitySwarm` scheme includes the `GravitySwarmTests` target. A differently named simulator can be substituted when necessary.

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

While active, the app renders at 30 fps and performs exactly two fixed 1/60-second simulation steps per rendered frame under normal cadence. The accumulator retains at most six simulation steps (0.1 seconds) for bounded catch-up. This avoids the former 0/2-step oscillation caused by using the same nominal 30 Hz interval for both rendering and simulation.

When the leader is below the movement threshold and the remapped control vector remains in the deadzone, rendering drops to 15 fps. The fixed simulation remains at 60 Hz, so an idle rendered frame normally advances four simulation steps. The first active input frame requests 30 fps again before simulation is advanced.

The implementation avoids SpriteKit physics bodies and updates lightweight Swift structs instead. Separation uses a preallocated uniform grid and evaluates each nearby pair once with symmetric forces. Rounded-boundary shapes are cached for the leader and swarm radii. SpriteKit nodes and screen-scale textures are created once and reused.

Debug builds log 300-frame average update CPU time and delivered frame interval in the `Performance` category. `SKView` and the `SpriteView` options/debug-options initializers are unavailable on watchOS 26.5, so watchOS cannot publicly enable `ignoresSiblingOrder`, `showsFPS`, or `showsDrawCount` through this SwiftUI host.

Initial limits are conservative for Apple Watch battery and thermal behavior. Real motion feel and battery impact should be validated on physical Apple Watch Ultra hardware before increasing the maximum swarm size. Runtime logs use the `com.giffeler.gravityswarm` subsystem for motion source, calibration, final Crown changes, and Debug performance samples.

With Reduce Motion enabled, the initial swarm count is reduced from 48 to 24 and wander/follow acceleration is halved. The Digital Crown can still select the full configured range.

## Display Sleep

watchOS controls display sleep, Always-On dimming, the status area, and the displayed time to preserve battery life and reduce burn-in risk. Gravity Swarm runs as a normal foreground watchOS app and does not try to keep the display awake indefinitely. `.persistentSystemOverlays(.hidden)` is only a request to minimize eligible overlays; it does not hide the watchOS clock. When the system deactivates or backgrounds the app, the simulation and motion updates pause and resume when the app becomes active again.

## Simulator

The simulator does not provide live Apple Watch motion input. Simulator builds use an animated fallback vector so the leader and swarm remain testable.
