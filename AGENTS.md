# PinShot Repository Instructions

- Read DEVELOPMENT.md before development or review; use RELEASE.md for packaging and releases.
- Inspect the worktree first. Preserve unrelated user changes and keep each task scoped.
- Define acceptance criteria and failure behavior before editing. Add regression checks for bug fixes.
- Run `bash scripts/validate.sh` after code changes. Report any blocked or unexecuted checks honestly.
- Automated checks do not verify real screen recording permission, UI gestures, or actual translation output. Record manual results separately.
- Do not install, reset permissions, push, merge, or publish without user authorization for that operation.
- Use a consistent signing identity for local app updates; never silently substitute ad-hoc signing.
- Before an authorized app replacement, back up the installed bundle and warn that restarting can close pins.
- Work on feature branches and use PRs for master. Respect branch protection.
- For reviews, report actionable findings with severity, location, and trigger conditions; distinguish static risks from reproduced failures.
- The user authorizes subagents for independent verification during PinShot development and optimization. Delegate bounded checks; keep the main agent responsible for verifying evidence and integrating fixes.
- Follow the issue loop in DEVELOPMENT.md: record, confirm, fix, regression-test, independently recheck. Keep evidence in docs/testing/issue-log.md. Do not mark untested or blocked findings resolved.
- Keep status reports precise: implemented, automatically checked, manually verified, installed, pushed, merged, and released are different states.
