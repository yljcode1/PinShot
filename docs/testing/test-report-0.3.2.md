# PinShot 0.3.2 Test Report

- Date: `2026-03-26`
- Workspace: `/Users/yaolijun/Documents/PinShot`
- Source version: `0.3.2 (6)`

## Scope

This round focused on:

- internal code and logic cleanup without changing user-facing features
- consolidating automated validation utilities and image fixtures
- tightening capture placement bounds and reducing duplicated AppModel state transitions
- preparing a releasable `0.3.2` package and GitHub release asset

## Automated Validation

### 1. Debug build

Command:

```bash
swift build
```

Result: passed

### 2. Full automated checks

Command:

```bash
swift run PinShot --all-checks
```

Result: passed

### 3. Release build

Command:

```bash
swift build -c release --product PinShot
```

Result: passed

### 4. Packaged app validation

Command:

```bash
PinShot.app/Contents/MacOS/PinShot --all-checks
```

Result: passed

Observed tail:

```text
PASS - Exported PNG can be read back as an image
PASS - English OCR text plans translation into simplified Chinese
PASS - Chinese OCR text plans translation into English
PASS - Pinned capture width stays within the visible frame
PASS - Pinned capture height stays within the visible frame
PASS - Pinned capture layout reserves room for editing chrome
ACCEPTANCE CHECK PASSED
PASS - Acceptance workflow passes
ALL REQUESTED CHECKS PASSED
```

### 5. Release artifact

Artifact:

```text
dist/PinShot-0.3.2-macos-arm64.zip
```

Packaging notes:

- `PinShot.app` was assembled from `.build/release/PinShot`
- `Support/Info.plist` now reports `0.3.2 (6)`
- ad-hoc codesign completed and `codesign --verify --deep --strict PinShot.app` returned no output

## Optimization Summary

- Added shared check helpers in `Sources/PinShot/CheckSupport.swift`
- Reduced duplicated validation code in `SelfCheckRunner`, `AcceptanceCheckRunner`, and `QualityCheckRunner`
- Centralized zoom clamping and selected-capture refresh flow inside `AppModel`
- Kept all existing validation entrypoints and feature behavior unchanged
