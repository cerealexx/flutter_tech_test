# Cabina

A podcast app built with Flutter. Search podcasts, open a show to browse its
episodes, and stream an episode. A personal Library lets you keep the shows you
follow.

> This is the starting point for the Labhouse Flutter technical test. Please read
> the test brief you were sent alongside this repository before you begin.

## Requirements

- Flutter `3.41.x` (Dart `3.11.x`). The exact version is pinned in `.fvmrc`
  (`3.41.9`).
- An iOS Simulator / device or an Android emulator / device.

### Flutter SDK via FVM (recommended)

The project pins its Flutter SDK with [FVM](https://fvm.app) so everyone builds
against the same version. Install FVM and the pinned SDK once:

```bash
brew install fvm            # or: dart pub global activate fvm
fvm install                 # reads .fvmrc and installs Flutter 3.41.9
```

Then prefix Flutter/Dart commands with `fvm` (see below). For the IDE: VS Code
picks up the SDK automatically via `.vscode/settings.json`; in Android
Studio / IntelliJ set the Flutter SDK path to `<project>/.fvm/flutter_sdk`.

> Prefer managing Flutter yourself? Any `3.41.x` SDK works — just drop the `fvm`
> prefix from the commands below.

## Running

```bash
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs   # generates *.g.dart
fvm flutter run
```

The app targets **iOS and Android**. No API keys or accounts are required to run
the core app.

## Tech overview

- **State:** `flutter_bloc` (BLoC + Cubit), manual DI via
  `RepositoryProvider` / `BlocProvider`.
- **Navigation:** `go_router`.
- **Data:**
  - Discover / Search → [iTunes Search API](https://performance-partners.apple.com/search-api)
    (no key).
  - Show detail → the podcast's **RSS feed** (parsed with `package:xml`).
  - Audio → streamed with `just_audio`.
  - Local persistence → `shared_preferences` / `hive`.
- **Models:** `json_serializable` + `equatable` + `copyWith` (run `build_runner`
  after changing an annotated model).
- **Theming:** a `ThemeExtension` (`AppTheme`) — read colors via
  `context.appTheme`.

### Project layout

```
lib/
  app/            App widget + dependency injection
  common/         Theme, errors, networking, shared widgets, extensions
  discover/       Discover grid + favourites
  search/         Podcast search
  show_detail/    Podcast detail + RSS feed parsing + episodes
  player/         Audio player (just_audio)
  episode_insights/ Episode companion UI, state, repository and services
  library/        The user's followed podcasts
  router/         go_router configuration
  home/           Bottom-nav shell
```

## Tests

```bash
flutter test
```

A few example tests live under `test/` — use them as a pattern for any you add.

## Configuration — AI Companion

The episode companion starts automatically when an episode opens in **Now
Playing**. Tap the summary icon in the toolbar to open its drawer. It shows a
summary in the episode's predominant language followed by timestamped key topics.
Selecting a topic closes the drawer, seeks, and starts playback, including when
the player was paused.

Supply your own OpenAI API key at build/run time. The core app still works without
a key; the drawer explains that the companion is not configured.

```bash
fvm flutter run --dart-define=LLM_API_KEY=YOUR_OPENAI_API_KEY
```

The optional `OPENAI_SUMMARY_MODEL` define overrides the default
`gpt-5.6-terra`. Its replacement must support Responses API and strict JSON Schema
outputs. For example:

```bash
fvm flutter run --dart-define=LLM_API_KEY=YOUR_OPENAI_API_KEY \
  --dart-define=OPENAI_SUMMARY_MODEL=gpt-5.6-terra
```

Configuration lives in `lib/common/env/env.dart`. **Never commit a real key or
distribute a build containing your key.** Dart defines are embedded in the app;
they are configuration, not secret storage. This direct-client integration is for
local evaluation. A distributed app needs a trusted backend to protect a shared
key. OpenAI API billing is separate from a ChatGPT subscription. Opening an
uncached episode with a configured key automatically downloads its audio and
starts billable analysis; long episodes can take several minutes.

### Processing and cache

- `EpisodeInsightsCubit` owns route state and depends on a thin
  `EpisodeInsightsRepository`, which delegates to `IEpisodeInsightsService`.
  `PlayerPage.route()` provides both the player BLoC and companion Cubit through
  `MultiBlocProvider`. The page reads the provided Cubit and starts analysis once
  in `initState`; the provider closes it when the route is disposed.
  `EpisodeInsightsService` coordinates downloads, native audio preparation,
  transcription, summary generation, progress, and checkpoints. Its main flow is
  **read cache → download → transcribe chunks → summarize → save**.
  A single queue waits for cancelled work to clean up before starting the next
  analysis, so leaving and reopening the player cannot overwrite its files.
- Audio downloads stream to disk, independently of playback. OpenAI credentials
  are sent only to `api.openai.com`, never to the podcast host or redirects.
- `OpenAiInsightsService` uses `openai_dart` 8.1 (compatible with the project's
  Dart minimum) for typed transcription and Responses requests. SDK logging and
  automatic retries are disabled. The service owns the five-retry policy for
  both endpoints, cancellation, and validation of timestamps and topic references.
  A small interceptor blocks redirects and reads numeric `Retry-After` headers.
  The SDK receives one WAV fragment in memory at a time (at most 20 MB); the
  original episode continues to be downloaded and decoded through files.
- iOS uses AVFoundation; Android uses MediaExtractor/MediaCodec. They decode
  valid WAV PCM fragments of at most 120 seconds / 20 MB with two seconds of
  overlap. iOS converts to 16 kHz mono; Android preserves the decoded sample
  rate and mono/stereo channels. Native work runs off the main thread. MP3 and
  M4A are covered by native integration tests; other formats depend on the OS
  decoder. Live streams and DRM content are not supported for analysis.
- `/v1/audio/transcriptions` uses `whisper-1`, `verbose_json`, and segment
  timestamps. Fragment offsets become absolute positions. Overlapping repeated
  segments are deduplicated. Silence produces a clear empty-content message.
  If the final segment ends up to five seconds beyond the fragment, its end is
  clamped to the audio boundary; its valid start (used for topic playback) stays
  unchanged. Larger overruns and invalid starts are rejected.
- `/v1/responses` generates a 100–180-word summary and up to 12 key topics using
  strict structured output and `store: false`. The model returns segment IDs,
  not invented times. The app validates those IDs and resolves their positions.
  Transcripts exceeding 40,000 characters per request are summarized in complete
  blocks and reduced, preserving segment references and coverage.
- The original audio, transcript checkpoints, and final result are cached locally
  with versioned JSON manifests written atomically. Cache folders are identified
  by episode, URL, and processing version. Existing manifests remain compatible;
  their old content fingerprints and chunk counters are ignored. Leaving the player
  cancels outstanding work; reopening resumes after the last completed fragment.
  Closing only the drawer does not cancel analysis. Rejected HTTP requests are
  retried up to five times after the initial attempt, rebuilding the request and
  waiting 1, 2, 4, 8, then 16 seconds (or a numeric Retry-After, capped at 60
  seconds). Leaving the player cancels retries too. The manual retry button
  appears after those attempts fail. Transport failures are not automatically
  replayed because the original request might already have been accepted.
  A cancelled request already accepted by the service may still incur a charge.
- The progress bar and label use the same percentage: download occupies 0–10%,
  completed audio occupies 10–90%, and the final summary completes the remaining
  10%. Progress is based on media duration, with the feed duration as a fallback,
  rather than a fixed number of chunks (which varies with the WAV size limit).
  Without duration metadata, it holds at 10% until the final chunk is known.
  Only a complete result reaches 100%. Topic titles omit leading segment IDs or
  numbered dash prefixes, including when reading older cached results.
- A topic always plays the exact cached file that was analyzed. This avoids
  timestamp drift from a podcast host serving different inserted advertisements.
  Future visits use the cached audio from the start. A missing or empty audio file
  invalidates the saved analysis. For this technical exercise, files remain until
  the app's data is cleared: there is no automatic size limit or eviction.
  The app checks file existence and size, without rehashing its content. External
  modifications to a nonempty cached file are outside this demo's scope.
- AI failures stay inside the drawer. They do not stop the existing player.
  Transcripts, response bodies, and credentials are not logged. Approximate
  transcript alignment and codec seeking can affect the exact landing point.

**Transcription model lifecycle:** the official OpenAI documentation consulted on
25 October 2026 schedules `whisper-1` retirement for **26 February 2027**. The
transcription service is replaceable, but a new provider must return aligned
segment timestamps: changing only the model ID to `gpt-transcribe` does not
preserve that contract. Recheck availability before evaluating after this date.
See [transcription compatibility](https://developers.openai.com/api/docs/guides/transcription),
[structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs),
and [API key handling](https://developers.openai.com/api/reference/overview#authentication).

### Validation

Unit and widget tests use fake HTTP/native services and consume no API credits:

```bash
fvm flutter test
fvm flutter analyze
```

Native integration tests generate a WAV larger than 25 MB on the device and
check chunk sizes, original offsets, overlap, final-chunk handling, cancellation,
and seeking. Optional MP3/M4A cases use synthetic fixtures (no API calls):

```bash
# Terminal 1: ffmpeg is needed only to create these test fixtures.
bash tool/generate_audio_test_fixtures.sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory build/audio-fixtures

# Terminal 2: Android USB device (omit adb for iOS Simulator).
adb reverse tcp:8765 tcp:8765
fvm flutter test integration_test/audio_chunks_test.dart -d DEVICE_ID \
  --dart-define=AUDIO_FIXTURE_BASE_URL=http://127.0.0.1:8765
```

Without `AUDIO_FIXTURE_BASE_URL`, the WAV test runs and the compressed-format
tests are explicitly skipped. Restore the normal app with `fvm flutter run`
after running integration tests. For a real API smoke test, open an episode with
your key, wait for the result, select topics at the beginning/middle/end, then
reopen it and verify that the cached result appears without new API requests.

Flutter 3.41.9 with Xcode 27 may fail a generic simulator build because the Flutter
framework preparation script receives both architectures as one value. On Apple
Silicon, target a specific simulator, or build explicitly for arm64 after
`fvm flutter build ios --simulator --config-only` and `cd ios && pod install`:

```bash
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
```
