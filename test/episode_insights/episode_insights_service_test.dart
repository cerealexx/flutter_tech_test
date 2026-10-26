import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cabina/episode_insights/data/insights_cancellation.dart';
import 'package:cabina/episode_insights/data/services/audio_chunk_service.dart';
import 'package:cabina/episode_insights/data/services/audio_download_service.dart';
import 'package:cabina/episode_insights/data/services/episode_insights_service.dart';
import 'package:cabina/episode_insights/data/services/insights_cache_service.dart';
import 'package:cabina/episode_insights/data/services/openai_insights_service.dart';
import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:cabina/show_detail/models/episode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Chunks implements AudioChunkService {
  _Chunks({this.sourceDuration = const Duration(seconds: 200)});
  final Duration? sourceDuration;
  @override
  Future<AudioChunk> extract({
    required String sourcePath,
    required String outputPath,
    required Duration start,
    required InsightsCancellation cancellation,
  }) async {
    cancellation.check();
    await File(outputPath).writeAsBytes([0]);
    return AudioChunk(
      path: outputPath,
      start: start,
      end: Duration(seconds: start == Duration.zero ? 120 : 200),
      isLast: start != Duration.zero,
      sourceDuration: sourceDuration,
    );
  }
}

class _Transcriber implements TranscriptionService {
  final starts = <Duration>[];
  Future<void> Function()? beforeResult;
  @override
  Future<List<TranscriptSegment>> transcribe(
    AudioChunk chunk,
    InsightsCancellation cancellation,
  ) async {
    starts.add(chunk.start);
    await beforeResult?.call();
    cancellation.check();
    return [
      TranscriptSegment(
        id: '${chunk.start.inSeconds}',
        text: 'Topic',
        start: chunk.start,
        end: chunk.start + const Duration(seconds: 10),
      ),
    ];
  }
}

class _Summarizer implements SummaryService {
  int calls = 0;
  bool failOnce = false;
  @override
  String get model => 'test-summary';
  @override
  Future<EpisodeInsights> summarize(
    List<TranscriptSegment> segments,
    InsightsCancellation cancellation,
  ) async {
    calls++;
    if (failOnce) {
      failOnce = false;
      throw const InsightsException('Temporary analysis failure');
    }
    return EpisodeInsights(
      summary: 'Complete summary',
      topics: [
        KeyTopic(title: 'Topic', start: segments.last.start),
      ],
    );
  }
}

void main() {
  late Directory root;
  late InsightsCacheService cache;
  late EpisodeInsightsService service;
  late _Transcriber transcriber;
  late _Summarizer summarizer;
  var downloads = 0;
  const episode = Episode(
    guid: 'e1',
    title: 'Episode',
    audioUrl: 'https://example.com/a.mp3',
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('insights-cache-');
    cache = InsightsCacheService(root: () async => root);
    downloads = 0;
    transcriber = _Transcriber();
    summarizer = _Summarizer();
    service = EpisodeInsightsService(
      configured: true,
      cache: cache,
      downloader: AudioDownloadService(
        clientFactory: () => MockClient((_) async {
          downloads++;
          return http.Response.bytes([73, 68, 51, 0], 200);
        }),
      ),
      chunks: _Chunks(),
      transcriber: transcriber,
      summarizer: summarizer,
    );
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'complete analysis is cached and topic playback uses that exact file',
    () async {
      final first = await service.generate(
        episode,
        InsightsCancellation(),
        (_) {},
      );
      final second = await service.generate(
        episode,
        InsightsCancellation(),
        (_) {},
      );
      expect(first.insights, second.insights);
      expect(await service.cachedAudioUri(episode), first.audioUri);
      expect(downloads, 1);
      expect(transcriber.starts, [Duration.zero, const Duration(seconds: 118)]);
      expect(summarizer.calls, 1);
      expect(
        File(
          '${File.fromUri(first.audioUri).parent.path}/chunk.wav',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'progress uses completed audio duration and survives resuming',
    () async {
      final progressUpdates = <InsightsProgress>[];
      final cancellation = InsightsCancellation();
      await expectLater(
        service.generate(episode, cancellation, (progress) {
          progressUpdates.add(progress);
          if (progress.status == EpisodeInsightsStatus.transcribing &&
              (progress.fraction ?? 0) > 0.5) {
            cancellation.cancel();
          }
        }),
        throwsA(isA<InsightsCancelled>()),
      );
      final firstPass = progressUpdates.map((p) => p.fraction!).toList();
      expect(firstPass, orderedEquals([...firstPass]..sort()));
      expect(firstPass.last, closeTo(0.58, 0.00001));
      expect(
        (await cache.open(episode)).sourceDuration,
        const Duration(seconds: 200),
      );
      progressUpdates.clear();
      await service.generate(
        episode,
        InsightsCancellation(),
        progressUpdates.add,
      );
      expect(progressUpdates.first.fraction, closeTo(0.58, 0.00001));
      expect(progressUpdates.last.status, EpisodeInsightsStatus.summarizing);
      expect(progressUpdates.last.fraction, 0.9);
      expect(progressUpdates.every((p) => p.fraction! < 1), isTrue);
      expect(transcriber.starts, [Duration.zero, const Duration(seconds: 118)]);
    },
  );

  test(
    'feed duration supports native builds without duration metadata',
    () async {
      const timedEpisode = Episode(
        guid: 'with-feed-duration',
        title: 'Episode',
        audioUrl: 'https://example.com/a.mp3',
        duration: Duration(seconds: 200),
      );
      final fallback = EpisodeInsightsService(
        configured: true,
        cache: cache,
        downloader: service.downloader,
        chunks: _Chunks(sourceDuration: null),
        transcriber: transcriber,
        summarizer: summarizer,
      );
      final values = <double?>[];
      await fallback.generate(timedEpisode, InsightsCancellation(), (progress) {
        if (progress.status == EpisodeInsightsStatus.transcribing) {
          values.add(progress.fraction);
        }
      });
      expect(values, contains(closeTo(0.58, 0.00001)));
      expect(values.last, 0.9);
    },
  );

  test('cached numbered titles are cleaned without generating again', () async {
    await service.generate(episode, InsightsCancellation(), (_) {});
    final entry = await cache.open(episode);
    entry.insights = const EpisodeInsights(
      summary: 'Existing summary',
      topics: [
        KeyTopic(title: '46439_0 — Host banter', start: Duration(seconds: 5)),
      ],
    );
    await cache.save(entry);
    final legacy = entry.toJson();
    final legacyInsights = legacy['insights'] as Map<String, dynamic>;
    final legacyTopics = legacyInsights['topics'] as List<dynamic>;
    (legacyTopics.first as Map<String, dynamic>)['title'] =
        '46439_0 — Host banter';
    await File(
      '${entry.directory.path}/manifest.json',
    ).writeAsString(jsonEncode(legacy));
    final result = await service.generate(
      episode,
      InsightsCancellation(),
      (_) {},
    );
    expect(result.insights.topics.single.title, 'Host banter');
    expect(result.insights.topics.single.start, const Duration(seconds: 5));
    expect(summarizer.calls, 1);
  });

  test(
    'cancel and reopen retains completed chunks without retranscription',
    () async {
      final cancellation = InsightsCancellation();
      await expectLater(
        service.generate(episode, cancellation, (progress) {
          if (progress.status == EpisodeInsightsStatus.transcribing &&
              (progress.fraction ?? 0) > 0.5) {
            cancellation.cancel();
          }
        }),
        throwsA(isA<InsightsCancelled>()),
      );
      expect(transcriber.starts, [Duration.zero]);
      await service.generate(episode, InsightsCancellation(), (_) {});
      expect(transcriber.starts, [Duration.zero, const Duration(seconds: 118)]);
      expect(downloads, 1);
    },
  );

  for (final removeFile in [true, false]) {
    test(
      '${removeFile ? 'missing' : 'empty'} audio discards the checkpoint',
      () async {
        final first = await service.generate(
          episode,
          InsightsCancellation(),
          (_) {},
        );
        final audio = File.fromUri(first.audioUri);
        if (removeFile) {
          await audio.delete();
        } else {
          await audio.writeAsBytes([]);
        }
        expect(await service.cachedAudioUri(episode), isNull);
        await service.generate(episode, InsightsCancellation(), (_) {});
        expect(downloads, 2);
        expect(summarizer.calls, 2);
      },
    );
  }

  test(
    'a failed analysis does not block retry or repeat transcription',
    () async {
      summarizer.failOnce = true;
      await expectLater(
        service.generate(episode, InsightsCancellation(), (_) {}),
        throwsA(isA<InsightsException>()),
      );
      final result = await service.generate(
        episode,
        InsightsCancellation(),
        (_) {},
      );
      expect(result.insights.summary, 'Complete summary');
      expect(downloads, 1);
      expect(transcriber.starts, [Duration.zero, const Duration(seconds: 118)]);
      expect(summarizer.calls, 2);
    },
  );

  test(
    'reopening waits for cancelled work to clean up its temporary file',
    () async {
      final started = Completer<void>();
      final finishCleanup = Completer<void>();
      transcriber.beforeResult = () async {
        if (transcriber.starts.length == 1) {
          started.complete();
          await finishCleanup.future;
        }
      };
      final cancellation = InsightsCancellation();
      final first = expectLater(
        service.generate(episode, cancellation, (_) {}),
        throwsA(isA<InsightsCancelled>()),
      );
      await started.future;
      cancellation.cancel();
      final second = service.generate(episode, InsightsCancellation(), (_) {});
      await pumpEventQueue();
      expect(transcriber.starts, [Duration.zero]);
      finishCleanup.complete();
      await first;
      final result = await second;
      expect(result.insights.summary, 'Complete summary');
      expect(downloads, 1);
      expect(transcriber.starts, [
        Duration.zero,
        Duration.zero,
        const Duration(seconds: 118),
      ]);
      expect(
        File(
          '${File.fromUri(result.audioUri).parent.path}/chunk.wav',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'simultaneous requests share saved result instead of duplicate API work',
    () async {
      await Future.wait([
        service.generate(episode, InsightsCancellation(), (_) {}),
        service.generate(episode, InsightsCancellation(), (_) {}),
      ]);
      expect(downloads, 1);
      expect(summarizer.calls, 1);
    },
  );

  test('overlap removes duplicate segments and keeps timestamps monotonic', () {
    final previous = [
      const TranscriptSegment(
        id: 'a',
        text: 'Hello world.',
        start: Duration(seconds: 110),
        end: Duration(seconds: 120),
      ),
    ];
    final result = EpisodeInsightsService.mergeSegments(previous, [
      const TranscriptSegment(
        id: 'b',
        text: 'Hello world',
        start: Duration(seconds: 118),
        end: Duration(seconds: 121),
      ),
      const TranscriptSegment(
        id: 'c',
        text: 'Next topic',
        start: Duration(seconds: 121),
        end: Duration(seconds: 130),
      ),
    ]);
    expect(result.map((s) => s.id), ['a', 'c']);
  });

  test('partial overlap removes repeated words without losing new text', () {
    final result = EpisodeInsightsService.mergeSegments(
      [
        const TranscriptSegment(
          id: 'a',
          text: 'Ahora hablamos de energía solar.',
          start: Duration(seconds: 110),
          end: Duration(seconds: 120),
        ),
      ],
      [
        const TranscriptSegment(
          id: 'b',
          text: 'Energía solar. Después, almacenamiento.',
          start: Duration(seconds: 118),
          end: Duration(seconds: 125),
        ),
      ],
    );
    expect(result.last.text, 'Después, almacenamiento.');
    expect(result.last.start, const Duration(seconds: 120));
  });

  test(
    'legacy manifests are reused without hash checks or new API calls',
    () async {
      final original = await service.generate(
        episode,
        InsightsCancellation(),
        (_) {},
      );
      final manifest = File(
        '${File.fromUri(original.audioUri).parent.path}/manifest.json',
      );
      final legacy =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      legacy['hash'] = 'old-content-fingerprint';
      legacy['completedChunks'] = 2;
      await manifest.writeAsString(jsonEncode(legacy));

      final result = await service.generate(
        episode,
        InsightsCancellation(),
        (_) {},
      );
      expect(result.insights, original.insights);
      expect(result.audioUri, original.audioUri);
      expect(downloads, 1);
      expect(summarizer.calls, 1);
    },
  );

  test('corrupt manifests cannot restore timestamps', () async {
    final result = await service.generate(
      episode,
      InsightsCancellation(),
      (_) {},
    );
    final folder = File.fromUri(result.audioUri).parent;
    await File('${folder.path}/manifest.json').writeAsString('{broken');
    expect(await service.cachedAudioUri(episode), isNull);
  });
}
