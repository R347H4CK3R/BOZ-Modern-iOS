# Ledger — docs/superpowers/plans/2026-11-03-integrated-input.md
Base: b8387a1ed18d1d91249bd0b5188045e2121b8c89; branch feature/integrated-input.
Observed report #5 confirms v5 engine-thread input, fire/reload/swap dispatch and continued foreground/background lifecycle with native hiding OFF.
Ruling: use an integrated dylib retaining the engine, not a source-engine rewrite; an IPA load-command integration alone is not described as new engine code.
Ruling: initial suppression OFF; current device evidence validates input independently but does not validate native hiding. Cost: old artwork may remain during first phone test.
Ruling: implementation runs inline under existing autonomous authorization; no repeated design/continuation approval loops.

Task 1 complete locally: C math/ownership tests RED (missing APIs) -> GREEN; actual ARM64 analog publisher and aim-sync field tests GREEN.
Task 2 source implemented: app-owned multitouch surface, reset boundaries, manual aim flag verification and external-addon conflict gate. iOS ARM64 compilation and actual frame/tracking regression harnesses passed in CI run 41765802190.
Task 3 packaging unit tests RED (missing packager) -> GREEN, 6/6; pinned baseline recovered and SHA verified. Actual IPA packaging and all 70 retained-member hashes passed in CI run 41765802190.

Final review: independent reviewer found two important gesture bugs. Fixed normal-end look loss by separate surface/fire streams (new regression RED -> GREEN); preserve pending normal-end deltas and cancel only the canceled producer. Fixed stale FIRE tracking with generation invalidation after resets, including surface-generation refresh. Host regression runs actual tracking methods, intentionally removes the guard to reproduce the bug, then runs the guarded methods; passed in macOS CI run 41765802190. No additional important findings.
Build correction: iOS compiler rejected Swift-style Objective-C tracking selector names; corrected to beginTrackingWithTouch/continueTrackingWithTouch; subsequent compilation passed before these review fixes.

Ruling: editing captures background gameplay touches without producing movement/look; native pause/log top band remains accessible. This prevents native legacy gestures from activating while rearranging controls.

Final build: source 59dc5c3f4c228ceab298a4d50c3ed19b5a241b64; CI run 41765802190 succeeded. IPA SHA256 158398f2de38f4486c94212e864ed8b2d6fc444872650816a748f8c9f92d9ca9, 378303723 bytes, build 135.20. Module SHA256 7dccf11af777b6f12e908568fdf8c2a89339172d06902ccecb976186379ffe2b. Native game code/data and retained assets unchanged. Integrated-header Marmalade section/hash-seed checks also passed locally for original and Strata-inserted-ID orders. Physical-device movement feel and native artwork hiding remain unverified.
