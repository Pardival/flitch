# 0003 · Hold right ⌥ to talk, ⌃⌥Space fallback

- Status: Accepted (2026-11-08)

## Context
Push-to-talk needs both key-down and key-up events, globally. Carbon hot keys deliver press and release without any permission, but only for key combinations. A single modifier key (right ⌥) needs a `CGEventTap`, which requires the **Input Monitoring** permission.

## Decision
- Default: **hold right ⌥**, through a listen-only `CGEventTap` on flag changes. Onboarding explains the Input Monitoring prompt.
- Fallback when permission is missing or denied: a Carbon hot key, `⌃⌥Space` by default and customizable.
- Presses shorter than 0.3 s are ignored.

## Consequences
- One extra permission prompt in the default path. Users who refuse it still have a working shortcut.
- The tap only reads modifier flags. It never records other keys.
