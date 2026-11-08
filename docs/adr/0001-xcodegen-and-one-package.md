# 0001 · XcodeGen + one multi-target Swift package

- Status: Accepted (2026-11-08)

## Context
Hand-edited `.xcodeproj` files cause merge conflicts and are hard to review. Most of Flitch is logic (state machine, providers, voices, memory) that should be testable without Xcode or a UI.

## Decision
- The Xcode project is generated from `project.yml` by XcodeGen, and the `.xcodeproj` is git-ignored.
- All logic lives in one Swift package, `Packages/FlitchKit`, split into targets: Core, Providers, Voice, Memory, Character and Stage.
- Only `FlitchStage` may import AppKit/SwiftUI. `scripts/check-imports.sh` enforces this in CI.

## Consequences
- `swift test` runs the whole logic test suite headless, locally and in CI.
- Contributors install XcodeGen (`brew install xcodegen`) to open the app in Xcode.
