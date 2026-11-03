# BOZ Combat HUD v2

Adds a COD Mobile-inspired combat overlay with original outlined icons, translucent controls, press feedback and a bottom-center weapon-switch button. Adds a movable SWAP button to switch between carried weapons. Hold does not repeatedly cycle weapons.

Small experimental control add-on for Loader Fix v5 (build 135.8). No game reinstall is required. Keep BOZFreeShop v2 installed.

1. Close the game in Strata. If controls v1 is installed, delete its BOZControls.dylib before importing this replacement; keep BOZFreeShop.dylib.
2. Download BOZControls.dylib. In Strata's Tweaks screen, import it into the SAME folder that contains BOZFreeShop.dylib, assigned to Black Ops Zombies under its Tweak Folder setting.
3. Open the game. At the main menu, tap Controls, then Enable COD-style HUD.
4. Start a NEW round. Native Touch mode supplies left-side movement and swipe aiming. Hold FIRE to shoot, hold ADS to aim, tap RELOAD to reload, tap SWAP to switch guns. No target-based auto-fire is added. Existing native manual gestures remain available.
5. Controls > Move buttons allows dragging the four buttons; Controls > Finish moving buttons resumes input. Positions and sensitivity persist. Leave an uncovered area on the right for swipe aiming.

This is an initial touch-control adaptation inspired by COD Mobile, not a replacement for all native menus, movement artwork, gameplay, weapons, AI or animations. FIRE does not currently support dragging to aim; use a separate finger on the uncovered aim area. Native aim assist is unchanged.

Hide combat buttons stops add-on commands. Native Touch mode and sensitivity remain set; use the original game's Controls options to restore your preferred scheme. Remove only BOZControls.dylib to uninstall; retain the shop add-on.

Input state, button events and profile status are recorded in BOZDiagnostics/controls.log and session.log for the existing diagnostic reporter. No additional token is required.

Validation: manual input state tests, real ARM64 input-handler emulation and import-thunk dispatch tests. The build is checked for ARM64 and absence of a signature. Physical iPhone behavior and control feel still require testing. If the buttons do not appear, send the existing diagnostic report rather than reinstalling the whole game.
