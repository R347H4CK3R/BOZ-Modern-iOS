# Integrated manual input rebuild

Authorized scope: Chris requested an app-level COD Mobile-inspired input overhaul, manual aim/fire, no aim assist, then explicitly said Proceed. Maps and new weapons are deferred until controls are stable.

Keep the checksum-pinned Loader Fix v5 engine, assets, bundle identifier and saves. Integrate an ARM64 input module through a load command in the unsigned IPA. This is a binary-compatible input replacement, not reconstructed engine source. Do not overwrite the stable catalog until a phone test confirms it.

A dedicated UIKit multitouch surface owns active-gameplay touches, with a floating left movement stick and independent right swipe look. Combat buttons use the native action handlers already observed working in report #5. Native menus and the top pause/log band remain accessible. Clear state on cancellation, menus, pause, background and geometry changes. No target detection drives aim or fire.

Disable native autoAim in preferences and the current HUD player instance. Send the native analog event ABI: direction angle, magnitude, native speed, raw axis pair, left/right discriminator. Verify against the actual ARM64 publisher before shipping. Touch-scale/rotation signs need phone calibration.

Do not use the failed offscreen/forced-disabled HUD path. Native visibility suppression remains an explicit experimental option, OFF by default in this first integrated build. Movement/look ownership must work independently of suppression; old manual gameplay gestures cannot receive touches owned by the new surface. An external BOZControls dylib must be removed to prevent competing input systems. Free Shop v2 remains supported separately.

Alternatives considered: extending the external overlay leaves native touch gestures in control; a new engine would require source/content reconstruction. Chosen: integrated input ownership while retaining the known-running engine.

Delivery: a separately tagged test unsigned IPA, no stable catalog promotion. Preserve baseline binary and asset bytes except the added load command and plist build metadata. Publish measured checksums. Physical-device control feel, old-HUD suppression and whole-session stability are not established by CI.
