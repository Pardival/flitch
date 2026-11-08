# Packaging

## Releasing

1. Update `MARKETING_VERSION` in `project.yml` if you want (the tag wins for release builds).
2. `git tag v0.2.0 && git push origin v0.2.0`
3. `.github/workflows/release.yml` tests, builds `Flitch-0.2.0.dmg` (ad-hoc signed), writes release notes
   from the commits and publishes the GitHub Release.

Local build: `scripts/build-dmg.sh 0.2.0` (install `create-dmg` for the styled window).

## One-time setup (maintainer)

### Sparkle auto-updates

1. Build once so Swift Package Manager downloads Sparkle, then generate a key pair:
   `build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`
   (it stores the private key in your login Keychain and prints the public key).
2. Export the private key: `generate_keys -x sparkle_private_key.txt`.
3. Add two repository secrets: `SPARKLE_PRIVATE_KEY` (the file's content) and `SPARKLE_PUBLIC_KEY`.
   Delete the exported file afterwards.

Without these secrets, releases still work but the app doesn't check for updates.
The feed is `https://github.com/Pardival/flitch/releases/latest/download/appcast.xml`.

### Homebrew tap

1. Create the public repository `Pardival/homebrew-tap` (with a `Casks/` folder).
2. Create a fine-grained token with *Contents: read and write* on that repository only.
3. Add it as the `TAP_TOKEN` secret of this repository.

Each release then writes `Casks/flitch.rb` from `homebrew/flitch.rb.template`. Users install with
`brew install pardival/tap/flitch`. Homebrew still shows the Gatekeeper prompt, since the app isn't notarized.
