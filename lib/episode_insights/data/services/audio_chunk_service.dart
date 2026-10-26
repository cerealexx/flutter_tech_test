import 'dart:async';

import 'package:cabina/episode_insights/data/insights_cancellation.dart';
import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

// A replaceable native boundary, also used by deterministic tests.
// ignore: one_member_abstracts
abstract interface class AudioChunkService {
  Future<AudioChunk> extract({
    required String sourcePath,
    required String outputPath,
    required Duration start,
    required InsightsCancellation cancellation,
  });
}

class NativeAudioChunkService implements AudioChunkService {
  const NativeAudioChunkService();
  static const _channel = MethodChannel('cabina/audio_chunks');

  @override
  Future<AudioChunk> extract({
    required String sourcePath,
    required String outputPath,
    required Duration start,
    required InsightsCancellation cancellation,
  }) async {
    cancellation.check();
    final id = const Uuid().v4();
    // Dispatch extraction before registering cancellation so native sees start
    // before cancel, even if cancellation happens in the same event-loop turn.
    final operation = _channel.invokeMapMethod<String, dynamic>('extract', {
      'id': id,
      'sourcePath': sourcePath,
      'outputPath': outputPath,
      'startUs': start.inMicroseconds,
    });
    final unregister = cancellation.onCancel(() {
      unawaited(
        _channel
            .invokeMethod<void>('cancel', {'id': id})
            .onError<Exception>((_, _) {}),
      );
    });
    try {
      // Wait for native cleanup before allowing another job to use this file.
      final result = await operation;
      cancellation.check();
      if (result == null) throw const FormatException();
      final chunk = AudioChunk(
        path: outputPath,
        start: Duration(microseconds: result['startUs'] as int),
        end: Duration(microseconds: result['endUs'] as int),
        isLast: result['isLast'] as bool,
        sourceDuration: switch (result['sourceDurationUs']) {
          final int us when us > 0 => Duration(microseconds: us),
          _ => null,
        },
      );
      if (chunk.end <= chunk.start || chunk.start < Duration.zero) {
        throw const FormatException();
      }
      return chunk;
    } on PlatformException {
      cancellation.check();
      throw const InsightsException(
        'This audio could not be prepared for analysis.',
      );
    } on MissingPluginException {
      throw const InsightsException(
        'Audio analysis requires an iOS or Android build.',
      );
    } on FormatException {
      throw const InsightsException('The audio contains no readable samples.');
    } finally {
      unregister();
    }
  }
}
