# BOZ Free Shop v2 (Strata add-on)

v1 could freeze after its backup while invoking the game's native add/save routine. v2 does not invoke that routine. It updates the validated local balance field and persists credits through its own wallet on a background serial queue.

## Replace v1

1. Close BOZ completely; force-close Strata if it is frozen.
2. In Strata Tweaks, open the per-game BOZ-Free-Shop folder.
3. Delete or disable the old BOZFreeShop.dylib, then import the new BOZFreeShop.dylib. Keep only one enabled copy.
4. Keep BOZ-Free-Shop selected as BOZ's Tweak Folder.
5. Relaunch, wait for the main menu, and use Free Shop to add credits.
6. After the saved-balance message, close and reopen the game to test persistence.

This is a small unsigned dylib. No full-game download or reinstall is needed. Strata handles signing through its existing tweak setup.

## Wallet and diagnostics

The wallet is stored at Documents/BOZFreeShop/wallet.plist in the game's data container. Existing Documents .i3d saves are backed up under BOZShopBackups before grants. Keep the add-on enabled to restore this wallet. Removing the add-on does not remove the wallet file, but the unmodified game does not read the add-on wallet. The native credit/save files are not rewritten by v2.

Balance writes use the supported VM API after validating the game fingerprint, store singleton, vtable and current balance. Grants are capped at 1,000,000 total credits. Observed balance changes, including spending, are saved by the background queue. Wait for the saved confirmation before closing after a grant.

Shop status events are recorded in BOZDiagnostics/shop.log and appended to the session log used by the existing GitHub diagnostic reporter. Wallet contents and unrelated files are not uploaded. No Apple purchases or receipts are generated.

CI tests actual Foundation file creation/reload, changes resembling spending, limits, preservation on rejected writes and corrupt-wallet rejection; it compiles an unsigned ARM64 iPhone dylib. The pinned native credit code is also checked to validate the expected field layout. In-game UI, spending, lack of freezes and persistence on the phone remain physical-device tests.
