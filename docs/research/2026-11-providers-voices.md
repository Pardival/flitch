# Research: AI connection, voices, speech recognition, distribution

*November 2026. Prices and terms move fast. Third-party price figures disagree with each other, so check every number against the provider's official page before relying on it.*

## TL;DR: recommendations

| Topic | Recommendation |
|---|---|
| **One-click AI connection** | ① **Continue with ChatGPT** (Plus/Pro plan usage, open-source track) ② **Sign in with OpenRouter** (one account, every model) ③ API keys per provider (advanced) ④ local Ollama / LM Studio |
| **Claude, Gemini** | API key only. Using a consumer subscription in third-party apps is forbidden or closed. |
| **Web search** | The provider's built-in search through a `webSearch` capability on each adapter. On OpenRouter: the `openrouter:web_search` server tool. |
| **Speech-to-text** | Apple `SpeechAnalyzer` / `SpeechTranscriber` on-device (macOS 26, EN/FR/ES). Cloud option: OpenAI or Mistral. |
| **Voice at first launch** | **"Animal voice"** (procedural chirps, free, instant, offline) or **Apple voice**. So a new user needs zero extra accounts. |
| **Premium cloud voices** | ElevenLabs (quality and custom voice design), Cartesia (lowest latency), OpenAI / Mistral Voxtral / Gemini (cheap) |
| **Distribution** | DMG on GitHub Releases, our own Homebrew tap, an illustrated install guide, updates through Sparkle (EdDSA signatures, no Apple account needed). |

---

## 1. Connecting to the AI models

### 1.1 Continue with ChatGPT: subscription usage (new, Sept 2026)

OpenAI now lets ChatGPT **Plus/Pro** users spend **their plan's included usage** in third-party apps.

- **Eligibility:** plan usage is available to **all open-source partners**. Commercial apps get it only through a limited trial. Flitch qualifies as open source.
- **Flow:** OAuth / OIDC with PKCE (S256), loopback redirect `http://127.0.0.1:<port>/auth/callback`. Use `127.0.0.1` exactly, not `localhost`. Start the listener before opening the browser.
  - Authorize: `https://auth.openai.com/api/accounts/authorize`
  - Token: `https://auth.openai.com/api/accounts/oauth/token`
- **Client registration:** dynamic. The first sign-in uses `client_id=dynamic_agent_client` plus `agent_name_hint`. The callback returns an issued `oaiapp_…` id that we store and reuse.
- **Scopes:**
  - identity: `openid profile email`
  - plan usage: `offline_access resource.invoke chatgpt.tokens.use.direct`. Check that this scope was actually granted.
- **Inference:** **Responses API only** (`POST /v1/responses`), with `stream: true` and `store: false`. Available models come from `GET /v1/models` (entries with `visibility == "list"`).
- **Tokens:** refresh tokens **rotate**. Replace the access token, refresh token, expiry and scopes together, and store them in the Keychain.
- **Errors to handle:** `subscription_sharing_usage_limit_exceeded` and `subscription_sharing_usage_unavailable`, which can arrive mid-stream as `response.failed`. Flitch should explain the problem kindly and suggest another provider.
- **Limits and risks:**
  - The docs don't mention audio (TTS or transcription) or the web-search tool, so we **must not assume** they are covered.
  - The program is new, and its terms may change.
  - Branding rule: the button label must be "Continue with ChatGPT".

> For the general public, this is the best experience: one click, no extra cost for Plus users.

### 1.2 Sign in with OpenRouter

- **OAuth PKCE.** The user logs in on openrouter.ai and the app receives a **user-owned API key**.
  - **Localhost callbacks** are allowed on any port, but a code challenge is mandatory there.
  - Codes are single-use and expire after 10 minutes.
  - Exchange endpoint: `POST https://openrouter.ai/api/v1/auth/keys`.
- **Billing:** usage is billed to the **user's own OpenRouter credits**. We pay nothing and host nothing.
- **Models:** one account covers Claude, GPT, Grok, Gemini, DeepSeek, Mistral, Qwen, Kimi and more, with one API in OpenAI chat format.
- **Web search:** the `:online` plugin is **deprecated**. Use the **`openrouter:web_search` server tool**.
  - Engines: `auto` uses the provider's native search when it exists, otherwise Exa. Native searches are billed at the provider's price.
  - Exa price: about $4 per 1,000 results, so at most about $0.02 per search with 5 results. Sources disagree, so verify.
- **Trade-off:** the user has to buy credits. It is the right default for people with no ChatGPT plan, or who want Claude.

### 1.3 Direct API keys (advanced) and why there is no account login

| Provider | Account login possible? | Notes |
|---|---|---|
| **Anthropic (Claude)** | **No.** Since Feb 2026, Anthropic's terms state that Free/Pro/Max OAuth tokens may only be used in Claude.ai and Claude Code. Enforcement against third-party harnesses started April 2026. | Use an API key (Messages API). Native `web_search` tool. |
| **Google (Gemini)** | **No.** Sign in with Google gives identity only. The consumer Gemini CLI OAuth path was shut down on 18 June 2026, and using it in third-party apps violates policy. | Use an API key from AI Studio (free tier for Flash models). Search through Google Search grounding. |
| **OpenAI** | **Yes**, see 1.1. | An API key is still needed for voice and transcription. |
| xAI (Grok), DeepSeek, Mistral, Qwen (DashScope), Kimi (Moonshot) | No account login found | API keys. All offer **OpenAI-compatible** endpoints. Search support differs and must be checked per adapter. |
| Local (Ollama, LM Studio) | Not applicable | OpenAI-compatible server on localhost. No web search. |

**Architecture consequence:** we need three adapters.
1. **OpenAI Responses**, for the ChatGPT plan and OpenAI keys.
2. **OpenAI-compatible Chat Completions**, for OpenRouter, xAI, DeepSeek, Mistral, Qwen, Kimi, Ollama and LM Studio. Each provider is a preset with a base URL and capability flags.
3. **Anthropic Messages**.

Gemini also exposes an OpenAI-compatible endpoint, so it fits adapter 2, with a native adapter later if needed.

## 2. Voices (text-to-speech)

Budget assumption for a "typical user": about 20 questions a day with answers about 30 s long, so about 300 min a month, or about 270k characters. Answers are always read in full, so long answers raise this.

| Engine | Quality / style | Latency | EN/FR/ES | Approx. cost (300 min/month) | Notes |
|---|---|---|---|---|---|
| **ElevenLabs Eleven v3** | Best expressiveness (laughs, emotion tags) | Medium | ✓ | ~$0.10 / 1k characters → **~$27** | Free tier 10k characters/month. **Voice Design**: generate a custom "Flitch" voice from a prompt. |
| **ElevenLabs Flash v2.5** | Very good | ~75–300 ms | ✓ | ~$0.04–0.05 / 1k characters → **~$12** | Best quality-to-latency balance. |
| **Cartesia Sonic 3.6** | Very good; the vendor claims wins over v3 in FR/ES | **Fastest** (~40–90 ms) | ✓ (44 languages) | ~1 credit per character; plans from ~$5/month | Strong runner-up. |
| **OpenAI gpt-4o-mini-tts** | Good, **steerable with text instructions** (already in the prototype) | ~400 ms | ✓ | ~$0.015/min → **~$4.5** | Preset voices only. A deprecation notice was reported; check before relying on it. |
| **Mistral Voxtral TTS** | Good, 3 s voice cloning | Low | ✓ (9 languages) | $0.016 / 1k characters → **~$4.5** | Open weights are CC BY-NC and 4B parameters: too heavy for the user's Mac, and can't be bundled. |
| **Gemini 3.1 Flash TTS** (preview) | Good, steerable, 30 voices | n/a | ✓ | ~$10 / M audio tokens (25 tokens/s) → **~$4.5** | Preview status. |
| **Kokoro 82M** (on-device, CoreML, Swift package `speech-swift`) | Good in EN; **only one FR voice** (`ff_siwis`); 3 ES voices | Local | ~ | Free | Optional download of about 300 MB. |
| **Apple voices** (`AVSpeechSynthesizer`, Premium/Enhanced) | Correct, less "cute" | Instant | ✓ | Free, offline | Always available. Zero setup. |
| **Animal voice** (procedural, in Flitch) | Chirps in the rhythm of the text, in the spirit of animal-sound speech in games but our own sound | Instant | Any language | Free, offline | Unique to Flitch and works for any character pack. |

**Recommendation:**
- One `SpeechSynthesizer` protocol with these engines plugged in.
- Defaults: **Animal voice + bubble**, with Apple voice one click away.
- Cloud voices ordered as: ElevenLabs (premium, "signature voice" through Voice Design), Cartesia, OpenAI, Mistral, Gemini.
- **Settings:** a voice picker with a "▶ Try" button that speaks a sample sentence in the chosen language. Samples are cached.
- **Streaming:** start speaking at the first complete sentence of the LLM answer, then pipeline sentence by sentence. Target time to first sound: under 1.5 s.

## 3. Speech-to-text

- **Default:** Apple **`SpeechAnalyzer` + `SpeechTranscriber`** (macOS 26).
  - On-device, free and private. Supports EN, FR and ES among about 30 locales; check `SpeechTranscriber.supportedLocales`.
  - Model assets are downloaded once through `AssetInventory`.
  - Benchmarks show it faster than Whisper, but **FR/ES accuracy lags EN**.
- **Optional cloud:** OpenAI `gpt-4o-transcribe` / `gpt-realtime-whisper` (streaming), or Mistral Voxtral. Offered for users who find on-device accuracy too low.
- Push-to-talk audio is never stored on disk after transcription, unless a debug setting says otherwise.

## 4. Distribution without an Apple Developer account

- Unsigned apps (ad-hoc signed) are blocked on first launch. Since macOS 15 the user must click **System Settings → Privacy & Security → Open Anyway**. The right-click → Open trick no longer works.
- **Homebrew:** Homebrew 5.0 deprecated unsigned casks. Casks that fail Gatekeeper are **disabled in the official repo from Sept 2026**, and `--no-quarantine` is deprecated. So: **our own tap** (`brew install <user>/tap/flitch`). It still shows the Gatekeeper prompt.
- **Updates:** Sparkle 2 with EdDSA-signed appcasts on GitHub Releases. It doesn't need Apple notarization.
- **Mitigations:** an illustrated install page (3 screenshots) and a first-run hint. The $99/year notarization can be reconsidered once there are users; it's purely a release-pipeline change.

## 5. Decisions to validate

1. Onboarding order: **Continue with ChatGPT → Sign in with OpenRouter → API keys → Local**.
2. Default voice at first launch: **Animal voice** (zero setup) rather than Apple voice.
3. Premium voice partner to build the "Flitch signature voice": **ElevenLabs** (Voice Design).
4. Speech-to-text default: **Apple on-device**, with optional cloud.

## Sources

- OpenAI Sign in with ChatGPT: [quickstart](https://developers.openai.com/siwc/quickstart), [open-source sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [models & inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference), [help center](https://help.openai.com/en/articles/20001542-using-your-chatgpt-plan-in-other-apps-and-sites)
- OpenRouter: [OAuth PKCE](https://openrouter.ai/docs/use-cases/oauth-pkce), [web search server tool](https://openrouter.ai/docs/guides/features/server-tools/web-search)
- Anthropic subscription ban: [The Register](https://www.theregister.com/2026/02/20/anthropic_clarifies_ban_third_party_claude_access), [WinBuzzer](https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/)
- Gemini OAuth: [Puter tutorial](https://developer.puter.com/tutorials/gemini-oauth/), [opencode-gemini-auth](https://github.com/jenslys/opencode-gemini-auth), [Google AI forum](https://discuss.ai.google.dev/t/least-privilege-google-sign-in-for-gemini-image-transcription-using-each-customers-free-api-allowance/190985)
- TTS overviews: [Gladia](https://www.gladia.io/blog/best-tts-apis-for-developers-in-2026-top-7-text-to-speech-services), [Versely](https://www.versely.studio/blog/best-text-to-speech-api-2026), [invideo pricing](https://invideo.io/blog/ai-voice-model-pricing/)
- Cartesia: [Sonic 3.6](https://cartesia.ai/blog/sonic-3.6/)
- Mistral: [Voxtral TTS](https://mistral.ai/en/news/voxtral-tts)
- OpenAI audio: [gpt-4o-mini-tts](https://developers.openai.com/api/docs/models/gpt-4o-mini-tts.md), [audio model updates](https://developers.openai.com/blog/updates-audio-models)
- Gemini TTS: [invideo](https://invideo.io/blog/gemini-tts-ai-voice/), [Google Cloud pricing](https://cloud.google.com/text-to-speech/pricing?hl=es)
- Kokoro: [speech-swift guide](https://soniqo.audio/guides/kokoro), [kokoro-mlx](https://github.com/gabrimatic/kokoro-mlx)
- Apple SpeechAnalyzer: [WWDC25 session](https://developer.apple.com/videos/play/wwdc2025/277/), [benchmark (MacG)](https://www.macg.co/macos/2026/07/speechanalyzer-un-benchmark-confirme-que-la-transcription-dapple-bat-le-whisper-dopenai-309741)
- Homebrew: [5.0.0 release](https://brew.sh/2025/11/12/homebrew-5.0.0), [Acceptable casks](https://docs.brew.sh/Acceptable-Casks), [Workbrew](https://workbrew.com/blog/what-homebrew-5-0-0-means-for-your-mac-fleet)
