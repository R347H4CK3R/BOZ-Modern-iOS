# Ledger — docs/superpowers/plans/2026-11-03-integrated-input.md
Base: b8387a1ed18d1d91249bd0b5188045e2121b8c89; branch feature/integrated-input.
Observed report #5 confirms v5 engine-thread input, fire/reload/swap dispatch and continued foreground/background lifecycle with native hiding OFF.
Ruling: use an integrated dylib retaining the engine, not a source-engine rewrite; an IPA load-command integration alone is not described as new engine code.
Ruling: initial suppression OFF; current device evidence validates input independently but does not validate native hiding. Cost: old artwork may remain during first phone test.
Ruling: implementation runs inline under existing autonomous authorization; no repeated design/continuation approval loops.

Task 1 complete locally: C math/ownership tests RED (missing APIs) -> GREEN; actual ARM64 analog publisher and aim-sync field tests GREEN.
Task 2 source implemented: app-owned multitouch surface, reset boundaries, manual aim flag verification and external-addon conflict gate. iOS compilation pending CI.
Task 3 packaging unit tests RED (missing packager) -> GREEN, 6/6; pinned baseline recovered and SHA verified. Actual IPA packaging pending compiled module.
