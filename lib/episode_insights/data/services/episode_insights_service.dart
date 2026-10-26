// Avoid synchronous file operations in the playback UI isolate.
// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:io';

import 'package:cabina/episode_insights/data/insights_cancellation.dart';
import 'package:cabina/episode_insights/data/services/audio_chunk_service.dart';
import 'package:cabina/episode_insights/data/services/audio_download_service.dart';
import 'package:cabina/episode_insights/data/services/i_episode_insights_service.dart';
import 'package:cabina/episode_insights/data/services/insights_cache_service.dart';
import 'package:cabina/episode_insights/data/services/openai_insights_service.dart';
import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:cabina/show_detail/models/episode.dart';

class EpisodeInsightsService implements IEpisodeInsightsService {
  EpisodeInsightsService({
    required this.configured,
    required this.cache,
    required this.downloader,
    required this.chunks,
    required this.transcriber,
    required this.summarizer,
  });

  @override
  final bool configured;
  final InsightsCacheService cache;
  final AudioDownloadService downloader;
  final AudioChunkService chunks;
  final TranscriptionService transcriber;
  final SummaryService summarizer;
  Future<void> _queue = Future.value();

  @override
  Future<Uri?> cachedAudioUri(Episode episode) async {
    try {
      final entry = await cache.open(episode);
      return entry.audio?.uri;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<InsightsResult> generate(
    Episode episode,
    InsightsCancellation cancellation,
    void Function(InsightsProgress) progress,
  ) {
    // A reopened route waits for the cancelled job to finish cleaning up.
    final task = _queue.then((_) => _generate(episode, cancellation, progress));
    // The caller receives failures; the queue stays available for the next job.
    _queue = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<InsightsResult> _generate(
    Episode episode,
    InsightsCancellation cancellation,
    void Function(InsightsProgress) progress,
  ) async {
    cancellation.check();
    final entry = await cache.open(episode);
    cancellation.check();
    if (entry.insights != null && entry.summaryModel == summarizer.model) {
      return InsightsResult(
        insights: entry.insights!,
        audioUri: entry.audio!.uri,
      );
    }
    if (!configured) {
      throw const InsightsException('AI Companion is not configured.');
    }

    var lastFraction = 0.0;
    void report(InsightsProgress update) {
      // Better duration metadata must not move the displayed percentage back.
      lastFraction = (update.fraction ?? 0).clamp(lastFraction, 0.99);
      progress(InsightsProgress(update.status, fraction: lastFraction));
    }

    await _download(episode, entry, cancellation, report);
    await _transcribe(entry, episode.duration, cancellation, report);
    cancellation.check();
    report(
      const InsightsProgress(EpisodeInsightsStatus.summarizing, fraction: 0.9),
    );
    final insights = await summarizer.summarize(entry.segments, cancellation);
    cancellation.check();
    entry
      ..insights = insights
      ..summaryModel = summarizer.model;
    await cache.save(entry);
    return InsightsResult(insights: insights, audioUri: entry.audio!.uri);
  }

  Future<void> _download(
    Episode episode,
    CachedEpisode entry,
    InsightsCancellation cancellation,
    void Function(InsightsProgress) progress,
  ) async {
    if (entry.audio != null) return;
    progress(
      const InsightsProgress(EpisodeInsightsStatus.downloading, fraction: 0),
    );
    final audio = await downloader.download(
      url: Uri.parse(episode.audioUrl),
      directory: entry.directory,
      cancellation: cancellation,
      onProgress: (fraction) => progress(
        InsightsProgress(
          EpisodeInsightsStatus.downloading,
          fraction: (fraction ?? 0) * 0.1,
        ),
      ),
    );
    entry.audioName = audio.uri.pathSegments.last;
    // Keep a completed download even if the user has just left the page.
    await cache.save(entry);
  }

  Future<void> _transcribe(
    CachedEpisode entry,
    Duration? feedDuration,
    InsightsCancellation cancellation,
    void Function(InsightsProgress) progress,
  ) async {
    void reportProgress() {
      final total = entry.sourceDuration ?? feedDuration;
      final processed = total != null && total > Duration.zero
          ? (entry.duration.inMicroseconds / total.inMicroseconds).clamp(0, 1)
          : 0.0;
      // Download: 0–10%, transcription: 10–90%, summary: final 10%.
      progress(
        InsightsProgress(
          EpisodeInsightsStatus.transcribing,
          fraction: entry.transcribed ? 0.9 : 0.1 + 0.8 * processed,
        ),
      );
    }

    while (!entry.transcribed) {
      cancellation.check();
      reportProgress();
      final file = File('${entry.directory.path}/chunk.wav');
      try {
        final chunk = await chunks.extract(
          sourcePath: entry.audio!.path,
          outputPath: file.path,
          start: entry.nextStart,
          cancellation: cancellation,
        );
        cancellation.check();
        entry.sourceDuration = chunk.sourceDuration ?? entry.sourceDuration;
        reportProgress();
        final segments = await transcriber.transcribe(chunk, cancellation);
        cancellation.check();
        entry
          ..segments = mergeSegments(entry.segments, segments)
          ..duration = chunk.end
          ..transcribed = chunk.isLast;
        if (chunk.isLast) entry.sourceDuration = chunk.end;
        final next = chunk.end - const Duration(seconds: 2);
        if (!chunk.isLast && next <= entry.nextStart) {
          throw const InsightsException('Audio preparation made no progress.');
        }
        entry.nextStart = next < Duration.zero ? Duration.zero : next;
        await cache.save(entry);
        reportProgress();
      } finally {
        if (await file.exists()) await file.delete();
      }
    }
  }

  static List<TranscriptSegment> mergeSegments(
    List<TranscriptSegment> previous,
    List<TranscriptSegment> incoming,
  ) {
    final result = [...previous];
    String normalize(String text) => text.toLowerCase().replaceAll(
      RegExp(r'[^\p{L}\p{N}]', unicode: true),
      '',
    );
    for (final segment in incoming) {
      final last = result.lastOrNull;
      if (last != null && segment.start < last.end) {
        if (segment.end <= last.end ||
            normalize(last.text) == normalize(segment.text)) {
          continue;
        }
        final previousWords = last.text.split(RegExp(r'\s+'));
        final incomingWords = segment.text.split(RegExp(r'\s+'));
        var repeatedWords = 0;
        for (
          var count = 1;
          count <= previousWords.length && count <= incomingWords.length;
          count++
        ) {
          final suffix = previousWords.skip(previousWords.length - count);
          if (normalize(suffix.join(' ')) ==
              normalize(incomingWords.take(count).join(' '))) {
            repeatedWords = count;
          }
        }
        if (repeatedWords == incomingWords.length) continue;
        // The overlap's words already represented by the previous segment must
        // not introduce a backwards topic timestamp.
        result.add(
          TranscriptSegment(
            id: segment.id,
            text: incomingWords.skip(repeatedWords).join(' '),
            start: last.end,
            end: segment.end,
          ),
        );
      } else {
        result.add(segment);
      }
    }
    return result;
  }
}
