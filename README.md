# Cabina — Flutter technical test

Cabina is a podcast app for iOS and Android. You can discover and search for
podcasts, browse their episodes, save favourites, subscribe to shows in your
Library, and listen to episodes. The AI Companion adds an episode summary and
key topics that you can tap to jump to the relevant part of the audio.

This README covers how to run the project, my priorities for the existing app,
the Companion's implementation, and my reflections on the exercise.

## Requirements and setup

- Flutter **3.41.9**, pinned in `.fvmrc`, with Dart **3.11.x**.
- An iOS Simulator/device or an Android emulator/device.
- For iOS: macOS, Xcode and CocoaPods. The project's minimum iOS version is 15.0.
- For Android: the Android SDK and a JDK compatible with the project's Gradle
  setup; Java 17 is the configured source/target version.

The project uses [FVM](https://fvm.app) to select its Flutter SDK:

```bash
brew install fvm # Alternatively: dart pub global activate fvm
fvm install
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter run
```

Run these commands from the repository root. If several devices are connected,
use `fvm flutter devices` and pass `-d DEVICE_ID` to `fvm flutter run`.
If you manage Flutter yourself, use the pinned version and omit the `fvm`
prefix. For Android Studio/IntelliJ, set the Flutter SDK path to
`<project>/.fvm/flutter_sdk`.

### Required environment variables

**The core app does not require any API keys.** Discover and Search use the
public iTunes Search API, and playback uses the podcasts' RSS feeds and audio
URLs. Generating new Companion results requires your own OpenAI API key.

The app reads configuration through compile-time Dart environment declarations
in `lib/common/env/env.dart`. Pass values with `--dart-define`; exporting a shell
variable or adding a `.env` file alone does not configure the app.

| Variable | Required? | Purpose/default |
| --- | --- | --- |
| `LLM_API_KEY` | Only for generating Companion results | Your OpenAI API key. Empty by default; the rest of the app still works. |
| `OPENAI_SUMMARY_MODEL` | No | Summary model; defaults to `gpt-5.6-terra`. A replacement must support the Responses API and strict JSON Schema output. |
| `AUDIO_FIXTURE_BASE_URL` | No; integration tests only | HTTP base URL for the optional synthetic MP3/M4A fixtures. See Validation. |

To run with the Companion enabled:

```bash
fvm flutter run --dart-define=LLM_API_KEY=YOUR_OPENAI_API_KEY
```

To explicitly select the summary model:

```bash
fvm flutter run --dart-define=LLM_API_KEY=YOUR_OPENAI_API_KEY \
  --dart-define=OPENAI_SUMMARY_MODEL=gpt-5.6-terra
```

The key shown above is a placeholder. **Never commit a real API key**, including
in IDE launch settings or configuration files, and do not distribute a build
containing your key. Dart defines are embedded in the binary; they are not
secret storage. This direct integration is only for local evaluation.

Opening an uncached episode with a configured key automatically downloads its
audio and starts analysis, which can incur API charges. Long episodes can take
several minutes. Without a key, the drawer shows a not-configured state unless
a compatible result is already cached.

## Architecture

I kept the existing feature structure and its flow from widgets to BLoCs/Cubits,
repositories and services:

- `flutter_bloc` manages state; `RepositoryProvider` and `BlocProvider` provide
  dependencies. Shared dependencies live in `AppDependencyInjection`, while
  Search, show detail, playback and Companion state belong to their routes.
- `go_router` handles navigation; its configuration is under `lib/common/router`.
- Services handle iTunes/RSS requests, local storage, audio playback and analysis.
  `just_audio` provides playback, and `shared_preferences` stores favourites and
  subscriptions. Companion audio and analysis are saved as files.
- Models use `equatable`, handwritten state/copy methods and, where applicable,
  `json_serializable`. Rerun `build_runner` after changing an annotated model.

## Task 1 — Prioritized plan and fixes

Task 1 covers repairs to existing functionality and refactors needed to follow
the proposed architecture. Summary and key-topic generation belong to Task 2.
My priority order was **Library → RSS Feed → Favourites → Player → Search**.

### 1. Library

**Problem.** The original implementation bypassed the proposed architecture.
Subscriptions were stored locally without shared reactive state, so users had
to restart the app to see changes in their Library. The subscription button
also had no error state of its own and did not account for Library loading or
failure states.

**Fix.** I introduced an app-scoped `LibraryCubit`, a `LibraryRepository` and an
`ILibraryService` implementation backed by SharedPreferences. Library and
`SubscribeButton` now read the same immutable state. Optimistic updates change
the UI immediately and roll back if persistence fails, with an error associated
with the affected podcast. The button is disabled while Library loads; a load
failure links to Library, where the user can retry. A **300 ms throttle** on
`SubscribeButton` limits repeated taps.

**Notes.** Since this app has not launched, I deliberately left out migrations
from legacy Library storage to keep the implementation lean. In a real product
with subscriptions stored in a database, I would probably expose a single
`toggleSubscription` operation using podcast IDs. The subscription relationship
should not need a copy of the podcast's title, author and artwork; this local
implementation stores that information so it can render Library on its own.

`SharedPreferencesLibraryService` also validates several malformed storage
formats. Some of that defensive handling may be more than this exercise needs;
I would revisit it against a real persistence contract. The repository itself
simply delegates to the service.

### 2. RSS Feed

**Problems.** The duration parser only accepted `HH:MM:SS`. Other formats could
throw an unhandled error and leave a podcast's detail page loading indefinitely.
Required feed data was also barely validated: for example, a missing audio URL
could reach a null assertion instead of a recoverable error state.

**Fix.** Durations now support plain seconds, `MM:SS` and `HH:MM:SS`. Missing or
invalid durations are treated as unknown optional metadata, so they do not
prevent playback. Invalid XML, a missing channel, or an episode without a title
or audio URL now produce a `FeedParseException`, which the existing BLoC maps
to the error screen with a Retry action. These cases no longer leave a spinner
running indefinitely.

**Notes.** Retry has limited value when the source feed itself is broken: the
user cannot fix its contents. In a real product, I would favour validating and
filtering out content that does not meet our requirements before listing it.
If we owned the content, I would also report those errors through observability
tools so we could fix them without exposing users to broken episodes. For now,
one episode missing required data causes the whole feed to fail; deciding
whether to hide that episode or reject the show is a product decision.

There is a related unresolved case in `ShowCard`: it passes `artworkUrl!` to
`PosterImage` even though artwork is not guaranteed. Library, show detail and
the player already provide fallbacks. I left that remaining assertion outside
this fix because choosing a fallback or excluding shows without artwork belongs
to the same broader content-quality decision.

### 3. Favourites

**Problem.** With no saved favourites, the repository returned an immutable
empty list, and tapping the heart tried to mutate it and threw an exception.
With saved favourites, the Cubit mutated the existing state's list, so emitting
the next state did not reliably trigger the UI update.

**Fix.** The toggle now copies the IDs into a new list before changing them,
emits a new state, and persists that list. This fixes both the first-favourite
crash and the stale heart state without expanding the feature's scope.

**Note.** If favourites were persisted remotely, I would debounce writes while
keeping immediate UI feedback, since this toggle is easy to tap repeatedly.

### 4. Player

**Problems.** Leaving the player route closed its BLoC without disposing the
repository, so audio kept playing. Opening other episodes could then leave
several players running at once. At the end of an episode, progress did not
reset and pressing Play did not restart it. During an active playback drag,
incoming position updates also competed with the user's slider position,
making the thumb jump around; this was especially noticeable on iOS.

**Fixes.** Closing `AudioPlayerBloc` now cancels its stream subscriptions and
disposes the repository and underlying player. Completion resets the displayed
position, and pressing Play after completion seeks to zero before starting
again. `SeekBar` keeps a local preview while dragging and sends one seek when
the user releases it; seek events are processed sequentially to avoid overlap.

**Note.** I generally avoid filling code with defensive early returns for
unlikely edge cases that have little practical effect on the UX. I kept the
lifecycle guards here because audio streams and asynchronous player operations
make races during route disposal quite plausible.

### 5. Search

**Problem.** Every keystroke triggered a request. Besides unnecessary traffic,
responses could arrive out of order and replace the latest results with results
for an older query.

**Fix.** Search now waits for **300 ms without another edit** before requesting
results. A `restartable()` event handler and cancellation checks prevent old
handlers from emitting results or errors. Clearing the query resets the state
immediately. Requests already sent may finish, but their stale responses cannot
overwrite the current search.

## Task 2 — AI Companion approach and key decisions

I treated this exercise as a hypothetical way to show how I would handle the
provided specs technically, even where I would challenge their practicality in
a real product. Keeping API secrets in a client app would be inappropriate, and
asking each device to generate the same content independently would also mean
a poor waiting experience and unnecessarily high costs.

In production, I would put a backend between the app and the AI provider and
choose a generation strategy based on the product's needs:

- **Generate on ingestion.** If the podcast provider offered webhooks, new
  episodes relevant to our catalogue could automatically enter a pipeline that
  creates summaries and key topics with timestamps before anyone opens them.
- **Generate on first demand.** To avoid processing content nobody listens to,
  the first request could trigger generation and cache the result for everyone
  else. Only that first listener would wait for generation; later listeners
  would reuse the same result.

Either way, credentials would stay on the backend and summaries, topics and
timestamps would live in our database. We should generate once and share the
result, instead of repeating the work for every user and storing separate local
copies. The implementation below accepts the brief as a proof of concept.

### Product behaviour

Analysis starts automatically when an episode opens in **Now Playing**, without
waiting for a separate Generate action. This uses the time the user spends
listening to get the result ready sooner. A summary icon in the app bar opens
a drawer; its badge indicates that analysis is in progress.

The drawer shows progress, a summary in the episode's predominant language, and
up to 12 key topics with timestamps. Tapping a topic closes the drawer, seeks
to its position, and starts playback even if the player was paused. Companion
failures stay inside the drawer and do not stop normal playback.

Closing the drawer leaves analysis running. Leaving the player route cancels
its outstanding work. A later visit reuses a complete result or resumes from
the saved transcription checkpoint.

### Processing and architecture

`EpisodeInsightsCubit` owns the route's UI state. It depends on
`EpisodeInsightsRepository`, which delegates to `IEpisodeInsightsService`.
`EpisodeInsightsService` coordinates the workflow:

```text
Read cache → download audio → prepare/transcribe fragments → summarize → save
```

I separated downloading, native audio preparation, transcription, summarization
and caching so those responsibilities can be tested and replaced independently.
The main decisions were:

- **Download to disk independently of playback.** The full episode is not held
  in memory. The downloader uses a separate HTTP client that never receives the
  OpenAI authorization header.
- **Prepare bounded audio fragments.** AVFoundation on iOS and
  MediaExtractor/MediaCodec on Android decode WAV PCM fragments of at most
  120 seconds and 20 MB, with two seconds of overlap. iOS converts to 16 kHz
  mono; Android preserves the decoded sample rate and mono/stereo channels.
  The SDK receives one fragment in memory at a time.
- **Ground timestamps in the transcript.** `openai_dart` sends fragments to
  `whisper-1` and requests segment timestamps. Fragment offsets become absolute
  episode positions, and repeated text in overlaps is deduplicated. The summary
  model references existing segment IDs; the app validates those references
  and resolves their timestamps rather than asking the model to invent times.
- **Use structured output.** The Responses API uses a strict JSON schema and
  `store: false`. The prompt asks for a 100–180-word summary, in the original
  predominant language, and up to 12 topics. Large transcripts are processed in
  complete blocks of up to 40,000 characters and reduced into a final result,
  keeping references to the original segments. Transcript content is explicitly
  treated as source material, not as instructions.
- **Show progress across the actual work.** Downloading accounts for 0–10%,
  transcription for 10–90%, and the final summary for the remaining 10%.
  Transcription progress uses audio duration, with RSS duration as a fallback.
  If duration is unknown, it waits at 10% until the final fragment is known.
  Only a complete result reaches 100%.

The transcription boundary requires aligned segment timestamps. Replacing its
provider would mean preserving that contract, not just changing a model name.
MP3 and M4A have native integration-test coverage; other supported file formats
depend on the operating system's decoder. Live streams and DRM content are
outside this analysis pipeline's scope.

### Cache, cancellation and retries

The cache stores the downloaded audio, transcription checkpoints and final
analysis in the app's support directory. Its key includes the episode GUID,
audio URL and processing version. Versioned JSON manifests are written through
a temporary file and renamed into place, and the summary model must match
before a saved result is reused. Changing the summary model can reuse the audio
and transcript while generating a new summary.

A checkpoint is saved after each successfully transcribed fragment, so retries
and later visits do not repeat all completed work. A completed download is also
reused; an interrupted partial download starts again. A single processing queue
waits for cancelled work to clean up before starting the next job, avoiding
conflicts when the player is closed and immediately reopened.

Topic playback uses **the exact cached audio that was analyzed**. Podcast hosts
can serve different dynamically inserted ads on separate downloads, which would
otherwise shift timestamps. Subsequent visits also start playback from the cached
file. Missing or empty audio invalidates its saved analysis. For this exercise,
there is no cache size limit or automatic eviction; files remain until the app's
data is cleared. File existence and size are checked, but contents are not
rehashed on every visit.

For both OpenAI endpoints, failed HTTP responses can trigger **five retries
after the initial attempt**, waiting 1, 2, 4, 8 and 16 seconds, or a numeric
`Retry-After` value capped at 60 seconds. SDK retries are disabled so there is
only one retry policy. Requests are rebuilt for each attempt, and leaving the
route cancels the request or wait. Transport failures are not automatically
replayed because the original request may already have been accepted. Other
failures, such as invalid output, also surface directly. The drawer provides a
manual retry when analysis fails.

OpenAI requests do not follow redirects, and credentials, transcripts and
response bodies are not logged. Cancelling locally cannot undo processing that
the API has already accepted, so that work may still incur a charge. Transcript
alignment and codec seeking can also make topic landing points approximate.

### What I would improve in the Companion UI

I would have liked to spend more time on the UX/UI. An action at the end of the
app bar that opens a drawer gives a technical demo plenty of room, but I do not
think it is the best final experience. I would explore showing topic markers
directly on the playback bar, with a floating hint displaying the topic title
when pressed.

## Validation

Unit and widget tests cover the repaired features and Companion behaviour using
fake HTTP/native services, without consuming API credits:

```bash
fvm flutter test
fvm flutter analyze
```

Native integration tests exercise audio chunk sizes, offsets, overlap,
final-fragment handling, cancellation and seeking on iOS/Android:

```bash
fvm flutter test integration_test/audio_chunks_test.dart -d DEVICE_ID
```

That command generates a WAV larger than 25 MB on the device. To also run the
MP3/M4A cases, generate synthetic fixtures and serve them locally. `ffmpeg` is
only needed to create these fixtures:

```bash
# Terminal 1, from the repository root:
bash tool/generate_audio_test_fixtures.sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory build/audio-fixtures

# Terminal 2, for an Android device/emulator connected through adb:
adb reverse tcp:8765 tcp:8765
fvm flutter test integration_test/audio_chunks_test.dart -d DEVICE_ID \
  --dart-define=AUDIO_FIXTURE_BASE_URL=http://127.0.0.1:8765
```

For iOS Simulator, omit `adb reverse`. Without `AUDIO_FIXTURE_BASE_URL`, the
compressed-format cases are explicitly skipped. Restore the normal app with
`fvm flutter run` after the integration tests.

For a real API smoke test, open an episode with a configured key, wait for its
summary, try topics near the beginning, middle and end, and reopen the episode
to check that its cached result appears without another generation request.

If a generic iOS Simulator build fails because Flutter's framework preparation
receives both architectures as one value, target a specific simulator. The
existing Apple Silicon workaround is to run
`fvm flutter build ios --simulator --config-only`, then, from `ios/`:

```bash
pod install
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
```

## Time spent and use of AI tools

The exercise took **approximately eight hours**, including iterations, code
review, manual testing on iOS and Android, and real summary generations.

Knowing I would need to explain and defend the code, I spent much more time
understanding the changes than producing them. At times, I felt I might have
finished a particular change faster by writing it myself, without the cognitive
debt of reviewing generated code. Still, I wanted to reproduce my current
workflow as closely as possible, using **Codex with GPT Astra**.

I used **Plan mode** to agree on each change before switching to implementation.
For this exercise, I kept that planning lightweight, without introducing a full
spec driven development workflow.

My process was:

1. I started with a visual review of every feature on both iOS and Android,
   noting what was broken and what could be improved.
2. I kept each feature or fix in a focused commit, so I could revisit its diff
   and explain the decisions behind it without unrelated changes getting in
   the way.
3. I proposed a plan for each feature/fix, including the technical requirements,
   and worked with the agent to implement and refine it.
4. I mostly stayed in one local chat, without worktrees, to make the diffs
   easier to follow and digest. I only used a parallel agent when a fresh
   context was useful for a focused subtask within the same feature or fix.
5. I iterated by reading diffs and asking the agent to explain any fragment I
   did not fully understand or would have approached differently. AI assisted
   with implementation, refactoring, tests and explanations; reviewing those
   changes was a substantial part of the work.
6. I focused on preserving the proposed architecture and keeping the code lean
   enough to explain confidently, challenging unnecessary abstractions and
   defensive guards for unlikely edge cases.

## Conclusions and personal reflections

### Code

- **Models, state and dependency injection.** I find the absence of `freezed`
  and `get_it` makes this code more verbose than the setup I would usually
  choose: `freezed` could reduce model/state boilerplate, while `get_it` could
  simplify dependency registration and access. I kept the existing conventions
  for this exercise.
- **DTOs.** External data mapping currently happens in service methods or
  directly in app models. I would consider dedicated DTOs to give transport
  formats and domain models clearer responsibilities.
- **Images.** For a real app, I would replace `Image.network` with
  `CachedNetworkImage`; the dependency is already present, but `PosterImage`
  still uses `Image.network`. If we owned the content infrastructure, I would
  also use a CDN with image transformation APIs to request dimensions and pixel
  densities appropriate to the display size, reducing download and decoding
  work.
- **Layout details.** A small personal preference: I deliberately avoided a
  general layout refactor and kept the existing structure. I would gradually
  extend the use of `Row`/`Column` spacing where it replaces repetitive
  `SizedBox` gaps cleanly; `SubscribeButton` already uses it.

### Features

**Keep listening while browsing.** Users should be able to leave the page where
they started an episode and continue listening while exploring the app. I would
add a floating mini-player and keep one active playback session, replacing the
episode when the user starts another one. The player provider would move into
`AppDependencyInjection`, above the router. Route disposal would then stop being
the playback lifecycle boundary: explicit public BLoC events/operations would
handle stopping or replacing an episode, while `close()` would still perform
final cleanup when the shared player is disposed.

**Expose playback outside the app.** Users should also see what is playing and
be able to control it when the app is in the background or the screen is locked.
I would start with
[just_audio_background](https://pub.dev/packages/just_audio_background), which
extends the existing `just_audio` player with background playback and controls
in media notifications, on the lock screen and through headset buttons. Its
single-player model fits the shared playback session proposed above. We would
provide episode metadata, complete the required Android/iOS configuration and
keep the player alive independently of the route.

If we needed more control over the available actions or their behaviour, I
would use [audio_service](https://pub.dev/packages/audio_service) directly,
with a custom `AudioHandler` around `just_audio`. Both options provide the
Flutter bridge to system media controls; the app UI and external controls would
share the same player and playback state.
