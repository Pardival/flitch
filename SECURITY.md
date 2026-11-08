# Security policy

Flitch handles API keys, OAuth tokens and microphone audio, so security reports matter a lot.

**Please do not open a public issue for a vulnerability.** Report it privately through
[GitHub security advisories](https://github.com/Pardival/flitch/security/advisories/new).
You'll get an answer within a week.

In scope:
- credentials leaking out of the Keychain;
- the OAuth loopback flow (ChatGPT, OpenRouter);
- audio or transcripts being stored or sent somewhere unexpected;
- update integrity (Sparkle).
