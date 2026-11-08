# Manual QA checklist

Run before each release on a clean macOS 26 user account if possible (fresh permissions).
Tick each line in the release PR. Automated tests cover the logic (`swift test`); this list covers what only
a real Mac, microphone and screen can show.

## Install and first launch

- [ ] DMG opens with the styled window; drag to Applications works.
- [ ] First launch is blocked; *Privacy & Security → Open Anyway* opens it ([install guide](install.md)).
- [ ] `brew install pardival/tap/flitch` installs the same version.
- [ ] Onboarding opens; every step's otter animation plays; Back / Continue work; Esc doesn't lose progress.
- [ ] Menu bar icon appears (template image, readable in light and dark menu bars).

## Permissions

- [ ] Microphone: prompt appears once; *Don't Allow* → the bubble offers *Open Privacy Settings*.
- [ ] Input Monitoring for right ⌥: prompt, then the key works after allowing (no relaunch needed, or a clear hint).
- [ ] Without Input Monitoring, ⌃⌥Space works, and Settings shows the fallback shortcut.
- [ ] Speech assets: on first talk in a new language, the model downloads, then transcription works.
- [ ] Accessibility (Dock mode, optional): *Allow* opens the prompt; the otter's walking range matches the Dock.

## Brain

- [ ] Continue with ChatGPT: browser sign-in, back to Flitch, label shows the account.
- [ ] Sign in with OpenRouter: browser flow, key saved, answers work.
- [ ] API keys (Claude, OpenAI, one preset): a wrong key is refused with a clear message; a good one is saved.
- [ ] Local model: Ollama running → works; stopped → clear message.
- [ ] Sign out removes the Keychain item (Keychain Access → *Flitch*).
- [ ] Web search on: "What's in the news today?" answers with sources in the answer card.

## Conversation (discreet mode)

- [ ] All four corners: bottom corners peek up; top corners come down head first under the menu bar.
- [ ] The otter appears on the screen that holds the mouse (test with two screens, and a notched MacBook screen).
- [ ] Holding < 0.3 s does nothing; silence hides the otter without calling the model.
- [ ] Live transcript while talking; release → thinking → first sentence spoken quickly.
- [ ] Interrupt: press the key while she speaks → she stops at once and listens.
- [ ] Follow-up within 15 s keeps the context ("And his death?").
- [ ] Bubble stays 15 s; hovering pauses the countdown; clicking opens the full answer card.
- [ ] Answer card: copy, replay, sources open in the browser, Esc closes it.
- [ ] Errors: Wi-Fi off → friendly message + *Try again* works when back online.
- [ ] Full-screen app (video): the corner panel still shows above it.

## Voices and transcription

- [ ] Each voice: *Test* plays the sample; selecting a premium voice without a key asks for the key.
- [ ] Animal voice is the default and works offline.
- [ ] Speed slider changes the speech rate.
- [ ] Cloud transcription (OpenAI / Mistral): asks for the key, then transcribes; Apple stays the default.
- [ ] English, French and Spanish: UI, transcription and voice follow the language setting.

## Memory and history

- [ ] About me (name, city): "What's the weather?" uses the city.
- [ ] "I support FC Barcelona" → chip *Remember this?* → ✓ keeps it (Settings › Memory), ✗ drops it.
- [ ] *Ask before remembering* off → chip says *Remembered*, no buttons.
- [ ] Edit, pin and forget a memory; *Forget everything* asks first.
- [ ] History lists the conversation; search ignores accents; delete one / delete all.
- [ ] Retention *Don't keep* → nothing is saved; switching to 90 days purges older conversations.

## Dock mode

- [ ] Mode → *On the Dock*: the otter appears on the Dock, walks, juggles, grooms, dances.
- [ ] After ~3 minutes idle she sleeps on her back; clicking wakes her up.
- [ ] Click her to talk (click, speak, click to send); the bubble shows above her and stays on screen near the edges.
- [ ] Auto-hidden Dock: she shows and hides with the Dock.
- [ ] Full-screen app: she hides, but still appears while you talk to her.
- [ ] Dock on the left or right: she hides (not supported yet), discreet mode still works.

## Updates and settings

- [ ] Settings › General › Updates: *Check for Updates…* finds a newer test release (Sparkle).
- [ ] Launch at login works after a restart.
- [ ] VoiceOver reads the otter, bubble text and buttons; Reduce Motion stops the waveform animation.
- [ ] Quit from the menu bar; relaunch keeps every setting.
