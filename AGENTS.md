# Twit Vid — repository instructions

## Project overview

**Twit Vid** (GitHub repository `Gitskrap/twit-vid`) is the Flutter Android application branded **Twitter vidéo**. It is an independent fork of [XFlow](https://github.com/Alchemist-Aloha/xflow) focused on public X/Twitter videos, local viewing preferences, and Google Cast.

- Android application ID: **`fr.twittervideo.client`**. Preserve this ID for in-place APK updates.
- Flutter package name: **`xflow`**, retained for import compatibility (`package:xflow/...`). Do not casually rename it.
- Android namespace: **`com.alchemistaloha.xflow`**, also retained to avoid breaking the native app.
- Flutter entrypoint: `lib/main.dart`.
- User-facing README: `README.md`; historical changelog: `TWITTER-VIDEO.md`.
- No affiliation with X Corp.

## Current app behavior

- The Videos tab presents videos longer than 15 seconds and recommends content from *local likes*, meaningfully watched videos, locally followed accounts, and favorite hashtags.
- Likes/dislikes are **local-only**, never POSTed to X. Displayed public like counts come from X's metadata.
- Dislikes exclude clips and related topics. Blacklisted hashtags override favorable signals.
- Search and hashtag pages can use X, public fallback, and cached media; these sources are not always available.
- Video playback starts muted; full-screen mode follows the feed rather than individual videos.
- Google Cast uses a LAN relay for MP4 streaming. Autoplay-next is implemented but receiver compatibility can vary.

## Source map

| Area | Purpose |
| --- | --- |
| `lib/core/` | X/public clients, models, caching and SQLite migrations |
| `lib/features/feed/` | Vertical feed, personalized discovery, hashtags, reactions |
| `lib/features/search/` | Video keyword and hashtag searches |
| `lib/features/player/` | media_kit player pool, seek bar, volume and fullscreen |
| `lib/features/cast/` | Chromecast integration and LAN video proxy |
| `lib/features/subscriptions/` | Local account following |
| `lib/features/settings/` | User preferences |
| `test/` | Flutter tests, with FFI tests for local SQLite |
| `android/` | Android platform configuration and permanent signing setup |

## Environment and commands

- Flutter SDK **3.44+** (GitHub Actions currently uses **3.47.6**).
- Dart SDK **3.12+**, JDK 17, Android SDK.

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter run
```

Local signed release build (requires configured private Android signing key):

```bash
flutter build apk --release --target-platform android-arm64
```

Never commit `android/key.properties`, Android keystore files, or authentication secrets.

## Publishing and versioning

- **Canonical Android CI / Release workflow:** [`.github/workflows/twitter-video-android.yml`](.github/workflows/twitter-video-android.yml).
- New releases must increment both version and build number in `pubspec.yaml`, plus the workflow's build/release version and filename.
- The workflow signs releases using GitHub secrets `ANDROID_KEYSTORE_BASE64` and `ANDROID_SIGNING_PASSWORD`. The key must remain stable for updates over the existing app.
- GitHub Releases and build artifacts are published in **`Gitskrap/twit-vid`**, not the old `Gitskrap/X-vid` address.
- `.github/workflows/release.yml` and `publish-twitter-video-apk.yml` are legacy automation, not the primary release procedure. Avoid invoking those unless specifically needed.
- A documentation-only change does **not** require a new Android version; the canonical workflow may nevertheless run because it triggers on pushes to `master`.

## Coding constraints

- Use Riverpod 3 APIs that exist in `flutter_riverpod: ^3.3.1`; do not assume `StateProvider` is supported.
- Preserve local user data across SQLite upgrades; add non-destructive migrations and tests for schema changes.
- Reactions stay local; do not revive X like/unlike mutation endpoints.
- Treat X/public APIs as unreliable. Keep fallback paths, visible error handling, cursor separation, and deduplication.
- Keep the long-video rule scoped to the main Videos tab, except where explicitly required elsewhere.
- Ensure UI changes work during Cast sessions and when no X account is connected.
- Do not overwrite or disable the permanent Android release signature.

## Validation and documentation

- Add focused tests under `test/` for code changes; use `sqflite_common_ffi` for SQLite.
- Run `flutter analyze`, `flutter test`, and validate Android APK builds for release changes.
- Update `README.md`, `TWITTER-VIDEO.md`, and the release notes when user-visible behavior changes.
- Keep public repository branding **Twit Vid** and Android branding **Twitter vidéo** distinct from internal package identifiers.
- Project license: MIT; preserve credits and notices for XFlow/Squawker.
