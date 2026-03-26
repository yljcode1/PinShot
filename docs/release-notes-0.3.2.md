# PinShot 0.3.2

## What changed

- internal code cleanup with no intended feature changes
- reduced duplicated logic in validation and capture state handling
- tightened oversized capture placement to keep inferred windows inside the visible frame
- expanded built-in validation and release documentation

## Validation

- `swift build`
- `swift run PinShot --all-checks`
- `swift build -c release --product PinShot`
