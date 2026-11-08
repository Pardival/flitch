<p align="center">
  <img src="docs/media/app-icon.png" width="160" alt="Flitch app icon: Hulo the little owl, in pixel art, wearing teal headphones, on a pink and aqua background with bubbles">
</p>

<h1 align="center">Flitch</h1>

<p align="center">
  <b>A voice assistant for macOS, embodied by a pixel-art animal: an otter, a red panda, an owl or an axolotl.</b><br>
  Hold a key, ask anything, and she answers out loud.
</p>

<p align="center">
  <a href="https://github.com/Pardival/flitch/actions/workflows/ci.yml"><img src="https://github.com/Pardival/flitch/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
</p>

<p align="center">
  <a href="README.fr.md">Français</a> ·
  <a href="https://pardival.github.io/flitch/">Website</a> ·
  <a href="docs/architecture.md">Architecture</a> ·
  <a href="https://github.com/Pardival/flitch/milestones">Roadmap</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

---

> **Status: early development**, heading for v0.1. Install: [guide](docs/install.md) (DMG or `brew install pardival/tap/flitch` once the first release is out).

<p align="center"><img src="docs/media/peek.gif" alt="Flitch peeking in from a corner and answering" width="504"> <img src="docs/media/dock.gif" alt="Flitch on the Dock" width="300"></p>

## What is Flitch?

Most AI assistants are a chat window. Flitch is a **little character that lives on your screen**:

1. **Hold right ⌥.** The otter peeks into a corner of your screen. At the top she comes down head-first; at the bottom she pops up.
2. **Talk.** She listens with her headphones on. Speech is transcribed on your Mac.
3. **Release.** She thinks, cracking a shell with her pebble, then **answers out loud** with a speech bubble.
4. She stays **15 seconds**, then goes away. Click the bubble to keep the full answer.

Ask her things like *"Tell me about Napoleon"* or *"What's in the news today?"*.

<p align="center">
  <img src="art/preview/otter_concept.png" width="720" alt="Concept sheet of the otter: idle, listening, thinking, talking, happy, waving, sleeping, peeking">
</p>

## Meet the characters

Pick your companion in **Settings › Personality**. Each one has its own look, gestures, animal voice and personality, and they all wear Flitch's teal headphones.

<p align="center">
  <img src="docs/media/characters.png" width="600" alt="The four characters waving, listening, thinking, happy and walking: Flitch the otter, Pip the red panda, Hulo the little owl and Axo the axolotl">
</p>

| | Character | Personality | While thinking | On the Dock |
|---|---|---|---|---|
| 🦦 | **Flitch**, the otter | Kind and curious | Cracks a shell with her pebble | Juggles pebbles, naps on her back |
| 🐼 | **Pip**, the red panda | Playful, a little mischievous | Nibbles a bamboo shoot | Juggles apples, sleeps curled in his tail |
| 🦉 | **Hulo**, the little owl | Wise and calm | Reads a little book | Hops around, preens, dozes all puffed up |
| 🩷 | **Axo**, the axolotl | Sweet and dreamy | Blows bubbles | Bounces bubbles, crawls along the Dock |

## Features

- **Bring your own AI, in one click.** Use *Continue with ChatGPT* (your Plus/Pro plan) or *Sign in with OpenRouter* (one account for Claude, Gemini, Grok, Mistral, DeepSeek, Qwen, Kimi…). You can also use API keys or a **local model** (Ollama, LM Studio).
- **Choose the model,** or let Flitch pick a recent one for the speed you want. Each model shows a price level (very cheap → expensive): OpenRouter's real prices, or a guess from the model's name for OpenAI.
- **Voices you can try before you pick:**
  - a free *animal voice* in otter chirps;
  - Apple voices;
  - premium voices from ElevenLabs, OpenAI, Cartesia, Mistral and Gemini.
- **Web search** through your provider's built-in search, for news and recent facts.
- **Memory you control:** an "About me" profile, plus things she learns. She asks before remembering anything, and everything stays on your Mac.
- **Four characters** (otter, red panda, little owl, axolotl) and **five tones:** Enthusiastic, Calm, Professional, Funny, Teasing.
- **Discreet mode** (a corner of the screen) or **Dock mode** (she walks, dances and naps on your Dock).
- English, French and Spanish.

## Privacy

- **No Flitch server.** Requests go straight from your Mac to the provider you chose.
- API keys and tokens live in the **macOS Keychain**.
- Audio is transcribed on-device by default and **never stored**.
- History and memories are a local SQLite file you can wipe at any time.
- **No telemetry.**

## Requirements

- macOS 26 or later

## Building from source

```bash
brew install xcodegen
xcodegen generate && open Flitch.xcodeproj
```

The core logic lives in `Packages/FlitchKit` and is tested with `swift test`.

## The art

Every character is drawn **in code**, from photos of the real animal, so anyone can tweak a pose or the palette:

```bash
python3 -m pip install -r art/requirements.txt
python3 art/otter.py --pack   # the otter
python3 art/red_panda.py      # Pip
python3 art/owl.py            # Hulo
python3 art/axolotl.py        # Axo
```

Each script writes its sprites into `Characters/<id>/sprites` and a contact sheet into `art/preview/<id>/`. The shared drawing tools are in `art/pixel.py`.

Characters come as **packs**: sprites, `pack.json` (animations, animal voice, Dock behaviour) and a personality in English, French and Spanish. Adding a folder to `Characters/` adds a character; no code needed.

## License

- Code: [MIT](LICENSE)
- Art (sprites, character designs): [CC BY 4.0](LICENSE-ART.md)
