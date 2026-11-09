# Release Workflow

1. **Prepare a feature branch**
   - Follow [DEVELOPMENT.md](DEVELOPMENT.md); work on a `codex/<task>` branch, not local master.
   - Ensure CI (`CI` workflow) is green.
   - Update changelog/README if needed.

2. **Build & smoke test**
   - `bash scripts/validate.sh`
   - Back up any existing bundle before rebuilding it. Use a clean staging directory.
   - `mkdir -p PinShot.app/Contents/{MacOS,Resources}`
   - `install -m 755 .build/release/PinShot PinShot.app/Contents/MacOS/PinShot`
   - `cp Support/Info.plist PinShot.app/Contents/Info.plist`
   - For local installs, select the same Apple Development identity on each update (`security find-identity -v -p codesigning`), then run `codesign --force --sign "$PINSHOT_SIGN_IDENTITY" PinShot.app` with that identity set. Verify with `codesign --verify --strict PinShot.app`. Do not replace a signed installation with an ad-hoc build: screen recording approval may no longer match.
   - `PinShot.app/Contents/MacOS/PinShot --all-checks`
   - Run `open PinShot.app` to verify hotkey, OCR, translation.
   - Record actual results using the manual validation template in DEVELOPMENT.md. Test the final installed app after any authorized replacement, including its version, build number, signing identity, and binary hash.
   - Apple Development signing is for local development. Public distribution requires a separate signing/notarization decision; never describe a development-signed build as notarized.

3. **Create PR to master**
   - Push the feature branch and open a PR targeting master.
   - Wait for CI and the repository's required reviews; merge through GitHub.
   - Never bypass branch protection or push a local merge directly to master.

4. **Tag & release**
   - Only publish with user authorization, after the PR is merged and required manual checks pass.
   - After PR merge and with a clean worktree: `git switch master && git pull --ff-only`
   - Rebuild and sign the release bundle from this exact commit; verify that its version and build number match Support/Info.plist. Do not package an old local bundle.
   - Verify the binary architecture before using the arm64 filenames below. Do not label a single-architecture build as universal.
   - `git tag vX.Y.Z && git push origin vX.Y.Z`
   - `ditto -c -k --keepParent PinShot.app dist/PinShot-X.Y.Z-macos-arm64.zip`
   - `scripts/build_dmg.sh X.Y.Z`
   - `gh release create vX.Y.Z dist/PinShot-X.Y.Z-macos-arm64.zip dist/PinShot-X.Y.Z-macos-arm64.dmg --title "PinShot X.Y.Z" --notes-file docs/release-notes-X.Y.Z.md`

5. **Post-release**
   - Announce build + share release link.
   - Update default download URLs if needed.
   - Bump version numbers in `Support/Info.plist` and README (next dev cycle).
