# 0005 · Modern glass UI; pixel art only for characters

- Status: Accepted (2026-11-08)

## Context
The first mockups used a retro GBA look everywhere. Feedback: the app should feel modern, with the charm coming from the character.

## Decision
- Every UI surface (bubble, answer card, onboarding, settings) follows macOS 26 conventions: frosted glass, large radii, the system font, grouped settings rows, switches and segmented controls, and a single teal accent.
- Pixel art is reserved for characters, rendered at integer scales with nearest-neighbour filtering.

## Consequences
- The UI uses native components (SwiftUI, `NSVisualEffectView` / glass) and gets accessibility and dark mode for free.
- The mockups in `docs/mockups` are the visual reference.
