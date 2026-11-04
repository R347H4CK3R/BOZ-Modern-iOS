# BOZ Combat HUD v4

Fixes v3 remaining at “Waiting for the game input bridge”: commands now run after the game’s regular engine-thread frame callback instead of depending on a yield import. The Controls menu identifies frame, input-manager and gameplay readiness separately. Native buttons are suppressed only when gameplay/input are ready.

COD Mobile-inspired transparent combat controls, native combat-button suppression, and a centered BUY / USE control. Manual fire only. This small unsigned add-on targets Loader Fix v5 (135.8); keep Free Shop v2.

1. Close the game completely in Strata.
2. Remove the previous BOZControls.dylib from the assigned per-game tweak folder, then import this replacement into the SAME folder. Keep BOZFreeShop.dylib; keep only one copy of BOZControls.
3. Launch the game. Controls > Enable COD-style HUD (if it is not already enabled), then start a NEW round to apply Touch mode.
4. Native movement and swipe aiming remain active. The replacement buttons are FIRE, ADS, RELOAD, SWAP, MELEE, GRENADE, CROUCH, TACTICAL and BUY / USE. Hold FIRE/ADS. Hold and release grenade buttons to throw; use tactical only when equipped. Tap SWAP to switch carried guns. Tap CROUCH or MELEE for their native actions.
5. BUY / USE appears near the center only when the game's own interaction predicate permits it. Native purchase/interaction text and prices move below it. Its background is transparent; it does not grant free wall weapons or bypass prices, perk requirements or proximity checks.
6. Controls > Move buttons lets you drag controls, including BUY / USE. Finish moving buttons resumes combat input. Leave the right aim area uncovered. Positions and sensitivity persist.

Enabled replacement mode hides and disables the matched native combat widgets and native buy Button/Image, preserving the buy text label. Hidden native buttons no longer receive hit tests. Movement/swipe-input handling, menus, health, ammo, score and perk indicators remain native. Existing manual touch gestures remain part of the native movement/aim layer.

Controls > Restore native buttons stops add-on commands, restores matched native widgets and restores the buy prompt's original position. Native Touch mode/sensitivity remain selected; restore those through the original Controls options if desired. To uninstall, restore native buttons, close the game, then remove only BOZControls.dylib.

This is an experimental replacement combat overlay, not an exact COD Mobile UI or a recreation of its gameplay. Native controls are suppressed at runtime; game assets are not deleted. If a widget is missing from the current UI tree, restoration waits until that tree is available again. Phone rendering, touch feel, pause transitions and layout still need device testing.

Diagnostics: BOZDiagnostics/controls.log and session.log include replacement status, matched widget count and buy/use events, using the existing report uploader and stored token.

Verified checks: manual input and queued taps, ARM64 native handlers for eight combat inputs, native POI event arguments and eligibility, native position setter, native hidden-child hit testing, ARM64 build and no code signature. These checks do not establish physical-device behavior.
