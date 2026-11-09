#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOG_DIR="$ROOT/.build/validation/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$LOG_DIR"
printf 'Validation logs: %s\n' "$LOG_DIR"

git -c core.fsmonitor=false diff --check 2>&1 | tee "$LOG_DIR/worktree-diff.log"
git -c core.fsmonitor=false diff --cached --check 2>&1 | tee "$LOG_DIR/staged-diff.log"
if [[ -n "${PINSHOT_DIFF_BASE:-}" ]]; then
    git -c core.fsmonitor=false diff --check "$PINSHOT_DIFF_BASE" HEAD 2>&1 | tee "$LOG_DIR/committed-diff.log"
fi
{
    git rev-parse HEAD
    git -c core.fsmonitor=false status --short
    sw_vers
    uname -m
    swift --version
} > "$LOG_DIR/environment.txt" 2>&1

for configuration in debug release; do
    swift build -c "$configuration" --product PinShot 2>&1 | tee "$LOG_DIR/$configuration-build.log"
    swift build -c "$configuration" --show-bin-path > "$LOG_DIR/$configuration-bin-path.txt" 2> "$LOG_DIR/$configuration-bin-path-error.log"
    BIN_DIR="$(< "$LOG_DIR/$configuration-bin-path.txt")"
    "$BIN_DIR/PinShot" --all-checks 2>&1 | tee "$LOG_DIR/$configuration-checks.log"
    "$BIN_DIR/PinShot" --lifecycle-check 2>&1 | tee "$LOG_DIR/$configuration-lifecycle.log"
done
printf 'Automated checks passed. Manual app validation is still required.\n'
