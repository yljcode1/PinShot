# PinShot Manual Test Execution Results

- Date: `2026-03-26`
- Workspace: `/Users/yaolijun/Documents/PinShot`
- Installed app: `/Applications/PinShot.app`
- Installed version: `0.3.1 (5)`

## Execution Summary

This pass attempted to execute the manual regression cases listed in `test-cases.md`.

- Directly executed items: `MT-001`, `MT-009`
- Environment-blocked items: `MT-002` to `MT-008`
- Key blocker: this session does not have Accessibility permission for scripted UI interaction with `System Events`

Observed blocker:

```text
66:70: execution error: “System Events”遇到一个错误：“osascript”不允许辅助访问。 (-1728)
```

## Case Results

| ID | Status | Result |
| --- | --- | --- |
| MT-001 | PARTIAL | `open /Applications/PinShot.app` succeeded and the `PinShot` process was running, but the menu bar icon itself could not be programmatically confirmed without Accessibility permission. |
| MT-002 | BLOCKED | Could not simulate the global hotkey or inspect the capture overlay because scripted key events / UI inspection are blocked by Accessibility permission. |
| MT-003 | BLOCKED | Could not complete the native screenshot selection + `Pin` choice without GUI automation. |
| MT-004 | BLOCKED | Could not script drag / zoom / opacity interactions without GUI automation. |
| MT-005 | BLOCKED | Could not execute the full OCR UI flow against a real captured image in this shell-only session. |
| MT-006 | BLOCKED | Could not execute the full Translate button UI flow in the pinned window without GUI automation. |
| MT-007 | BLOCKED | Could not manually draw annotations and click export without GUI automation. |
| MT-008 | BLOCKED | Could not open the menu bar history menu and click a recent capture without GUI automation. |
| MT-009 | PASS | App quit and relaunched successfully; the persisted defaults domain stayed unchanged across restart in this run. |

## Evidence

### Launch smoke test

Command:

```bash
open -a /Applications/PinShot.app
sleep 2
pgrep -fl '/Applications/PinShot.app/Contents/MacOS/PinShot|^PinShot$'
```

Observed:

```text
84952 /Applications/PinShot.app/Contents/MacOS/PinShot
```

### Process discovery

Command:

```bash
osascript -e 'tell application "System Events" to get name of every process'
```

Observed excerpt:

```text
..., Codex, ..., PinShot, ..., System Events, osascript, ...
```

### Quit and relaunch smoke test

Command:

```bash
DOMAIN=com.pinshot.PinShot
defaults read "$DOMAIN" > before.txt
osascript -e 'tell application "PinShot" to quit'
open -a /Applications/PinShot.app
defaults read "$DOMAIN" > after.txt
diff -u before.txt after.txt
```

Observed:

```text
quit_state=stopped
relaunch_state=running
--- defaults diff ---
```

Interpretation: no diff was produced for the persisted defaults domain during this restart pass.

## Automated Coverage Used As Fallback

These related automated checks passed in this same session:

- `AT-002` annotated export workflow passed via `swift run PinShot --acceptance-check`
- `AT-003` translation planning workflow passed via `swift run PinShot --acceptance-check`
- `IT-001` to `IT-003` rendering and mosaic integration checks passed via `swift run PinShot --integration-check`
- `ST-001` to `ST-004` built-in system self-check passed via `swift run PinShot --self-check`

## Recommendation

To finish the blocked manual items, rerun the matrix on a machine/session where:

- Terminal or Codex has Accessibility permission
- Screen Recording permission is granted
- the menu bar is visible for visual confirmation of the PinShot status item
