# BOZ Integrated Input — test build 135.20

This IPA keeps the existing BOZ engine and content and embeds its own input module. It is not the original engine source rebuilt from scratch. The stable source catalog is not changed by this test release.

## Install

Close the game. Remove BOZControls.dylib from the game's assigned Strata tweak folder so two input systems cannot compete. Keep BOZFreeShop.dylib if you use the working shop. Import BOZ-Integrated-Input-unsigned.ipa as an update to the existing BOZ entry; the bundle identifier is unchanged. Do not delete the existing data container. The IPA is unsigned and requires Strata/container signing.

## Input

Integrated input defaults ON. During active gameplay, begin a drag on the left 43% for a floating movement stick; swipe the right area to look. Move, look and fire with independent fingers. FIRE supports hold-and-drag aiming; ADS is hold. RELOAD, SWAP, MELEE, CROUCH, grenades and BUY / USE use the retained game handlers. Keep the top pause/log band available. Native menus take input when the round is paused.

Native aim assist is forced OFF in both its preference and current HUD-player flag. The module verifies those values before dispatching integrated movement/actions. No target scanning, snapping, tracking or automatic firing is implemented. Native weapon/game physics remain unchanged. Joystick speed, swipe direction/scale and sensitivity still need physical-device calibration; do not treat CI ABI tests as gameplay validation.

Cancellation, pause, opening Controls, background and rotation reset held actions and axes. Controls allows disabling integrated input, moving combat buttons and adjusting sensitivity. Finger ownership prevents a second movement/look finger stealing an active finger's role.

Native artwork suppression remains an experimental OFF-by-default option because previous native-widget edits caused device crashes. The integrated surface owns gameplay touches independently of that option, so underlying native touch gestures cannot receive those touches. Old HUD artwork may remain visible until suppression is confirmed safe. The old offscreen/forced-disable mutations are absent.

BUY / USE keeps the native purchase eligibility and prices; Free Shop credits remain a separate local addon. Centered price text follows the experimental suppression/relocation option.

## Testing and reporting

Test one short round: forward/back/strafe and diagonals, look while moving, fire-drag and ADS, reload and swap, release every finger, pause/resume and background/resume. Confirm no aim pull toward nearby enemies. Use Logs to report, and attach BOZDiagnostics/controls.log if a crash only produces startup data. Existing report credentials are not embedded or changed.

Build checks cover input math/ownership, actual ARM64 analog packet and aim-flag copy ABI, existing action-handler tests, real Frame callback in a host regression harness, Mach-O header-padding safety, unchanged code/data/assets and unsigned ARM64 output. Physical touch feel, full-session stability and native artwork suppression remain unverified until phone testing.
