# PinShot 0.3.1 Test Report

- Date: `2026-03-26`
- Workspace: `/Users/yaolijun/Documents/PinShot`
- Source version: `0.3.1 (5)`
- Installed app: `/Applications/PinShot.app`
- Installed version: `0.3.1 (5)`

## Scope

This round focused on:

- adding runnable automated checks for unit, integration, system, and acceptance levels
- documenting readable test cases for engineering and release review
- verifying both the source package and the installed app self-check entry

## Automated Validation

### 1. Debug build

Command:

```bash
swift build
```

Result: passed

Observed tail:

```text
Building for debugging...
[0/3] Write swift-version--1AB21518FC5DEDBE.txt
Build complete! (0.10s)
```

### 2. Release build

Command:

```bash
swift build -c release --product PinShot
```

Result: passed

Observed tail:

```text
[1/4] Write swift-version--1AB21518FC5DEDBE.txt
[3/5] Compiling PinShot AcceptanceCheckRunner.swift
[3/5] Write Objects.LinkFileList
[4/5] Linking PinShot
Build of product 'PinShot' complete! (6.38s)
```

### 3. Full automated checks

Command:

```bash
swift run PinShot --all-checks
```

Result: passed

Observed output:

```text
== UNIT CHECKS ==
PASS - Launch-at-login defaults to enabled
PASS - Hotkey configuration round-trips through preferences
PASS - Invalid hotkey data falls back to the default shortcut
PASS - History formatter trims OCR snippets
PASS - History formatter falls back for placeholder OCR text
PASS - Capture placement clamps into the visible frame
PASS - Capture chooser flips below the anchor near the bottom edge
PASS - Pin panel layout stays within bounds while adding editing chrome
PASS - Carbon modifiers preserve all supported flags
PASS - Hotkey display uses stable modifier ordering
PASS - Unknown key names use a stable fallback
PASS - Placeholder OCR text does not create a translation plan
PASS - English OCR text targets simplified Chinese translation
PASS - Chinese OCR text targets English translation
== INTEGRATION CHECKS ==
PASS - Annotation renderer exports PNG data
PASS - Annotated PNG output differs from the original image
PASS - Mosaic renderer produces an image for a clamped selection
PASS - Mosaic renderer output has valid dimensions
== SYSTEM CHECKS ==
PASS - Launch-at-login defaults to enabled
PASS - Hotkey configuration round-trips through preferences
PASS - History formatter uses fallback title
PASS - Chooser origin clamps into visible frame
PASS - Capture placement resolves image width
PASS - Capture placement resolves image height
PASS - Capture placement stays inside screen bounds
PASS - Panel layout preserves natural width
PASS - Panel layout expands for toolbar and inspector
PASS - Launch-at-login support matches bundle environment
SELF-CHECK PASSED
PASS - System self-check passes
== ACCEPTANCE CHECKS ==
PASS - Shortcut preference workflow persists and restores the chosen hotkey
PASS - Annotated pin renders a preview image
PASS - Annotated pin exports PNG data
PASS - Annotated export differs from the original capture
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

### 4. Installed app self-check

Command:

```bash
/Applications/PinShot.app/Contents/MacOS/PinShot --self-check
```

Result: passed

Observed output:

```text
PASS - Launch-at-login defaults to enabled
PASS - Hotkey configuration round-trips through preferences
PASS - History formatter uses fallback title
PASS - Chooser origin clamps into visible frame
PASS - Capture placement resolves image width
PASS - Capture placement resolves image height
PASS - Capture placement stays inside screen bounds
PASS - Panel layout preserves natural width
PASS - Panel layout expands for toolbar and inspector
PASS - Launch-at-login support matches bundle environment
SELF-CHECK PASSED
```

## Coverage Summary

- Unit checks cover preferences, hotkey formatting, history title generation, capture placement, chooser layout, panel sizing, and translation planning.
- Integration checks cover annotation rendering, PNG export, and mosaic generation against generated image fixtures.
- System checks cover the built-in self-check path used by the app entrypoint.
- Acceptance checks cover user-visible workflows for shortcut persistence, annotated export, translation planning, and pin layout readiness.

## Test Case Reference

- Readable case list: `test-cases.md`
- Manual regression checklist: `../../Samples/workflow-checklist.md`

## Notes

- This machine uses Command Line Tools at `/Library/Developer/CommandLineTools`; `swift test` is not relied on because the environment does not expose the usual `XCTest` / `Testing` modules.
- To keep validation runnable in this environment and in CI, the project now ships executable check entrypoints instead of a separate SwiftPM test target.
- Fully scripted system UI gestures such as invoking the native capture overlay still depend on macOS Screen Recording / Accessibility permissions and remain best validated in a manual release pass.
