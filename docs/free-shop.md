# BOZ Free Shop v1 (Strata add-on)

This is a small, unsigned ARM64 dylib for the working BOZ 1.3.5 Loader Fix v5. It does not replace or download the full game.

## Install

1. Close BOZ completely.
2. In Strata, open Tweaks. Create a folder named BOZ-Free-Shop and open that folder.
3. Use + / Import Tweak to import BOZFreeShop.dylib into it. Leave the add-on enabled.
4. Open BOZ's app settings and select BOZ-Free-Shop as its Tweak Folder. Tweak loading must be enabled.
5. Launch BOZ normally. At the main menu, use the Free Shop button to add 1,000 or 10,000 credits.
6. If the old shop is stuck on Accessing Store, cancel it and use Free Shop instead.

Strata signs the add-on using its existing signing setup. Keep the working game installed. To remove the add-on, select None for Tweak Folder, or disable BOZFreeShop.dylib, then restart BOZ.

## Behavior and verification

The add-on fingerprints the pinned credit routine before installing a GLView.show hook. It recognizes the store singleton and vtable, queues the selected credit amount, and invokes the original add/save routine from the render path. It caps local credits at 1,000,000 and makes a copy of existing Documents .i3d save files in BOZShopBackups before each grant.

Only a zero save status and the expected new in-memory balance produce a success message. Detailed results are written locally to Documents/BOZDiagnostics/shop.log. The addon does not contact Apple or submit purchases, receipts, or reports.

ARM64 emulation checks credit addition, the upper test balance, negative clamping and the exactly-once invocation of the original serializer. CI compiles the iPhone dylib and verifies it is ARM64, unsigned and under 1 MB. Phone UI, actual filesystem persistence after restart and in-game spending still require testing. The unmodified game remains the fallback; uninstalling the add-on does not restore or roll back granted credits.
