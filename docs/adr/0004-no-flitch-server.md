# 0004 · No Flitch server; user-owned credentials in the Keychain

- Status: Accepted (2026-11-08)

## Context
Flitch is free and open source. Running a backend would cost money and see users' questions.

## Decision
- The app talks directly to the provider the user picked: ChatGPT (plan usage), OpenRouter, API keys or a local model.
- OAuth flows use a loopback redirect on `127.0.0.1`.
- Every secret (API keys, access and refresh tokens) is stored in the macOS Keychain through `CredentialStore`, and never logged.

## Consequences
- Zero hosting cost and better privacy. Each user pays their own provider (or uses their ChatGPT plan).
- Providers that only allow subscription use inside their own apps (Claude, Gemini) require an API key or OpenRouter.
