# Release Workflow

1. **Prep dev branch**
   - `git checkout dev && git pull`
   - Ensure CI (`CI` workflow) is green.
   - Update changelog/README if needed.

2. **Build & smoke test**
   - `swift build -c release --product PinShot`
   - `rm -rf PinShot.app && mkdir -p PinShot.app/Contents/{MacOS,Resources}`
   - `install -m 755 .build/release/PinShot PinShot.app/Contents/MacOS/PinShot`
   - `cp Support/Info.plist PinShot.app/Contents/Info.plist`
   - `PinShot.app/Contents/MacOS/PinShot --all-checks`
   - Run `open PinShot.app` to verify hotkey, OCR, translation.

3. **Create PR to master**
   - `git checkout master && git pull`
   - `git merge --no-ff dev`
   - Push and open PR → ensure at least one approval (per branch protection).

4. **Tag & release**
   - After PR merge: `git checkout master && git pull`
   - `git tag vX.Y.Z && git push origin vX.Y.Z`
   - `ditto -c -k --keepParent PinShot.app dist/PinShot-X.Y.Z-macos-arm64.zip`
   - `scripts/build_dmg.sh X.Y.Z`
   - `gh release create vX.Y.Z dist/PinShot-X.Y.Z-macos-arm64.zip dist/PinShot-X.Y.Z-macos-arm64.dmg --title "PinShot X.Y.Z" --notes-file docs/release-notes-X.Y.Z.md`

5. **Post-release**
   - Announce build + share release link.
   - Update default download URLs if needed.
   - Bump version numbers in `Support/Info.plist` and README (next dev cycle).
