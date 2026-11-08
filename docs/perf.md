# Latency

Goal: **under 1.5 s** from releasing the talk key to the first sound with a cloud voice, and **under 0.5 s** for the speaking part with the animal or Apple voice.

## How a turn is timed

`ConversationOrchestrator` measures every turn from the moment the key is released and sends a `TurnTimings` event with the answer:

| Step | Meaning |
|---|---|
| `stt` | final transcript ready (speech is transcribed *while* you talk, so this should be short) |
| `token` | first text from the model |
| `sentence` | first speakable chunk handed to the voice |
| `audio` | first sound starts playing |

Turn on **Settings › General › Advanced › Show response timings** to see them in the bubble.

## What was done

- **Pipelining:** each sentence is synthesized as soon as it is complete, while the previous one plays (`VoicePipeline`).
- **Early first clause:** before anything has been spoken, a long opening sentence is cut at its first comma, semicolon or colon once it reaches 60 characters (`SentenceChunker(firstChunkMinLength:)`). Later sentences are never cut.
- **Cached previews** for cloud voices in Settings, so trying a voice twice costs nothing.

## Measurements (local, Apple silicon, Nov 2026)

Reproduce with `FLITCH_MEASURE=1 swift test --filter LatencyMeasurements`.

| Measure | Result |
|---|---|
| Animal voice: synthesize a 55-character sentence | **26 ms** |
| Apple voice: same sentence | **173 ms** |
| First chunk, model streaming ~60 tokens/s, early clause off | 433 ms after the first token |
| First chunk, early clause on (60 chars) | **249 ms** after the first token (−42%) |

With the on-device recognizer finishing almost at release, the speaking side adds about 0.3–0.45 s with local voices on top of the model's time to the first token.

## Still to measure

Cloud voices (ElevenLabs Flash, Cartesia, OpenAI, Mistral, Gemini) and cloud models need real API keys. Measure them with the timings overlay and add a row per provider here:

| Provider + voice | stt | token | sentence | audio |
|---|---|---|---|---|
| _to fill with real keys_ | | | | |
