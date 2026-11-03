# macOS distribution and updates

Linefold ships a universal (arm64 + x86_64) macOS 12+ application. The DMG supports first installation by dragging Linefold into Applications. The ZIP contains the same signed, stapled application and is the Sparkle update payload.

## Release configuration

`.github/workflows/release.yml` runs on `linefold-v*` tags, or manually with an existing tag selected. The tag must match `app/pubspec.yaml`; add `app/releases/<version>.md`. Increase both semantic version and integer build number for every update.

Required Actions secrets:

- `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY` (Developer ID Application).
- `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD` for notarization.
- `APPLE_MACOS_PROVISIONING_PROFILE_BASE64` for production iCloud entitlements.
- `LINEFOLD_SPARKLE_PRIVATE_KEY`: base64 Ed25519 seed. Its matching public key is the Actions variable `LINEFOLD_SPARKLE_PUBLIC_KEY`.

The update key is independent of other apps. Its local backup is in the login Keychain under Sparkle account `linefold-production`. Do not regenerate it between releases: installed clients trust the original public key. Never commit exported private keys. CI uses a temporary mode-600 file and removes signing material even after failure.

## Pipeline and channel

CI builds both architectures, configures the HTTPS feed and public key before signing, signs nested code and the app with Developer ID and hardened runtime, and checks Quick Look and cloud entitlements. It notarizes the ZIP, staples the app, repackages and Ed25519-signs the exact ZIP bytes, then generates and signs the appcast. It also creates, signs, notarizes and staples the DMG, verifies Gatekeeper acceptance, and writes SHA256SUMS.

The fixed feed is `https://github.com/robinfai/ianvs-markdown/releases/download/linefold-v0.1.2/appcast.xml`.

Version 0.1.2 is the channel anchor and first updater-enabled release. Older installations need one manual installation. New releases upload complete assets to a draft, publish it, then advance the anchor feed. Only the anchor appcast and its checksum entry change; historical ZIP/DMG bytes remain immutable. Both version and build must increase. Release jobs are serialized; releases remain marked as prereleases during this testing phase.

A published tag cannot be rebuilt or overwritten by this workflow. If publishing succeeds but advancing the anchor fails, retain that release and repair only the anchor appcast and SHA256SUMS after checking the signature and monotonic version with `advance_update_feed.py`. Do not replace public binaries; use a new version for binary corrections.

## App behavior

Linefold → Check for Updates… opens Sparkle's native UI. Release builds check daily; download and restart require user action. The normal Flutter exit path flushes workspace recovery and cancels exit if saving fails. Normal iCloud synchronization remains independent and gains no foreground progress indicator.

Feed and ZIP signatures are required, with archive verification before extraction. Sandbox access is limited to Sparkle's installer mach services. Debug builds do not start the updater; missing or invalid configuration is explained only on a manual update request.

## Validation

Run `python3 -m unittest discover -s app/tool -p 'test_*release.py'` and `python3 -m unittest discover -s app/tool -p 'test_advance_update_feed.py'`. RunnerTests checks native update configuration.

For local UI acceptance, build Release, fetch tools with `bash app/tool/fetch_sparkle.sh app/build/sparkle-tools`, then run:

```sh
bash app/tool/prepare_update_test.sh /absolute/path/Linefold.app /tmp/linefold-update-test /absolute/path/sparkle/bin 9135
python3 -m http.server 9135 --bind 127.0.0.1 --directory /tmp/linefold-update-test/downloads
```

Open `installed/Linefold Update Test.app` in the fixture. Its separate bundle ID disables cloud and uses a temporary test key and loopback feed. Create a draft, check updates, install/relaunch, and verify build 900002 and the recovered draft. Ad-hoc fixtures omit hardened runtime because they have no Team ID; production always requires Developer ID and hardened runtime. Apple notarization and production Gatekeeper acceptance are checked separately in release CI.

Implementation follows Trail's DMG/ZIP approach and [Sparkle's sandbox integration](https://sparkle-project.github.io/documentation/sandboxing/).
