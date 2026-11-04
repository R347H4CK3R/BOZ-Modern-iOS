# Integrated Manual Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship a test unsigned BOZ IPA owning movement/look and combat touches with native aim assist disabled.
**Architecture:** Pure C input math, UIKit multitouch ownership, engine-thread native ABI bridge, pinned-baseline packaging.
**Tech Stack:** C11, Objective-C/UIKit, Python ZIP/Mach-O tooling, macOS iOS clang, Unicorn.
**Spec:** docs/superpowers/specs/2026-11-03-integrated-input-design.md

## Global Constraints
- Manual aim/fire; native autoAim OFF. No map/weapon additions yet.
- Baseline SHA256 4afd45ed923807c5f02e63cba23ee6e9fd27a01abd7fc4db6232cb3c0cefae0c.
- No full engine-source claim. No stable catalog promotion before phone testing.
- Existing bundle identifier/assets retained. Experimental native suppression OFF initially.

## Review Focus
- Simultaneous movement/look/fire must not steal another finger's ownership.
- Pause/background/cancel must reset axes and buttons.
- Long drags/invalid floats must remain bounded and finite.
- Native analog ABI and no-aim-assist flags must match real code.
- Packaging must preserve code addresses, content hashes and absence of signatures.

### Task 1: Input math and ABI contract
Files: src/BOZTouchCore.h/.c, tests/test_touch_core.c, tests/test_integrated_native.py.
- [ ] Write failing tests for dead zone, diagonal normalization, look accumulation/consumption, cancellation and invalid floats.
- [ ] Implement bounded vector/dead-zone and frame-consumed relative look helpers.
- [ ] Execute actual analog publisher and native aim-assist copy routine under nonzero ASLR; verify packet and zero flag.
- [ ] Commit checked sources/tests.

### Task 2: Integrated input ownership
Files: src/BOZModernInput.m.
- [ ] Build from v5 observed action bridge, replace native movement/gesture dependence with a multitouch surface.
- [ ] Add floating movement stick and owned look finger; release/reset on every lifecycle boundary.
- [ ] Disable native aim-assist preference/current player flag and log verified writes.
- [ ] Keep hazardous suppression optional, OFF initially; reject external duplicate controls.
- [ ] Compile ARM64 unsigned module and run actual frame callback tests.

### Task 3: Package and verify unsigned IPA
Files: tools/package_integrated_input.py, tests/test_package_integrated_input.py, .github/workflows/build-integrated-input.yml.
- [ ] Add LC_LOAD_DYLIB only in existing verified header padding; preserve native code offsets and bytes.
- [ ] Embed module, bump build 135.20, preserve bundle ID/assets, reject any signature and verify load dependency.
- [ ] Test malformed/padding/signature/duplicate inputs and package with the verified pinned baseline.
- [ ] Run CI, independent review, publish test release and checksums. Leave stable catalog unchanged.
