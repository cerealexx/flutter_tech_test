import 'dart:io';
import 'dart:typed_data';

import 'package:cabina/episode_insights/data/insights_cancellation.dart';
import 'package:cabina/episode_insights/data/services/audio_chunk_service.dart';
import 'package:cabina/player/data/services/just_audio_player_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const chunks = NativeAudioChunkService();
  const baseUrl = String.fromEnvironment('AUDIO_FIXTURE_BASE_URL');

  Future<void> verify(File source, Directory temporary) async {
    var start = Duration.zero;
    var count = 0;
    while (true) {
      final chunk = await chunks.extract(
        sourcePath: source.path,
        outputPath: '${temporary.path}/chunk.wav',
        start: start,
        cancellation: InsightsCancellation(),
      );
      expect((chunk.start - start).inMilliseconds.abs(), lessThan(100));
      expect(chunk.duration, lessThanOrEqualTo(const Duration(seconds: 120)));
      expect(await File(chunk.path).length(), lessThanOrEqualTo(20000000));
      expect(chunk.end, greaterThan(start));
      expect(chunk.sourceDuration?.inMilliseconds, closeTo(150000, 150));
      count++;
      if (chunk.isLast) {
        expect(chunk.end.inMilliseconds, closeTo(150000, 150));
        break;
      }
      expect(count, lessThan(5));
      start = chunk.end - const Duration(seconds: 2);
    }
    expect(count, greaterThan(1));
    final player = JustAudioPlayerService();
    try {
      await player.open(source.uri.toString());
      for (final seconds in [5, 118, 148]) {
        final positioned = player.positionStream.firstWhere(
          (p) => (p.position.inSeconds - seconds).abs() <= 1,
        );
        await player.seekTo(Duration(seconds: seconds));
        // Seek while paused to avoid playing audible test tones.
        await positioned.timeout(const Duration(seconds: 10));
      }
    } finally {
      await player.dispose();
    }
  }

  testWidgets(
    'native decoder processes >25 MB audio, overlap and final chunk',
    (_) async {
      final temporary = await (await getTemporaryDirectory()).createTemp(
        'chunk-test-',
      );
      try {
        final source = File('${temporary.path}/source.wav');
        const rate = 48000;
        const dataSize = rate * 2 * 2 * 150;
        final header = ByteData(44);
        void text(int offset, String value) {
          for (var i = 0; i < value.length; i++) {
            header.setUint8(offset + i, value.codeUnitAt(i));
          }
        }

        text(0, 'RIFF');
        header.setUint32(4, dataSize + 36, Endian.little);
        text(8, 'WAVEfmt ');
        header
          ..setUint32(16, 16, Endian.little)
          ..setUint16(20, 1, Endian.little)
          ..setUint16(22, 2, Endian.little)
          ..setUint32(24, rate, Endian.little)
          ..setUint32(28, rate * 4, Endian.little)
          ..setUint16(32, 4, Endian.little)
          ..setUint16(34, 16, Endian.little);
        text(36, 'data');
        header.setUint32(40, dataSize, Endian.little);
        final sink = source.openWrite()..add(header.buffer.asUint8List());
        final second = Uint8List(rate * 4);
        for (var i = 0; i < 150; i++) {
          sink.add(second);
          await sink.flush();
        }
        await sink.close();
        expect(await source.length(), greaterThan(25000000));
        await verify(source, temporary);
        final cancelled = InsightsCancellation()..cancel();
        await expectLater(
          chunks.extract(
            sourcePath: source.path,
            outputPath: '${temporary.path}/cancelled.wav',
            start: Duration.zero,
            cancellation: cancelled,
          ),
          throwsA(isA<InsightsCancelled>()),
        );
      } finally {
        await temporary.delete(recursive: true);
      }
    },
  );

  for (final extension in ['mp3', 'm4a']) {
    testWidgets(
      'native $extension decoding preserves offsets and seeking',
      (_) async {
        final temporary = await (await getTemporaryDirectory()).createTemp(
          'chunk-test-',
        );
        final client = HttpClient();
        try {
          final response = await (await client.getUrl(
            Uri.parse('$baseUrl/source.$extension'),
          )).close();
          expect(response.statusCode, 200);
          final source = File('${temporary.path}/source.$extension');
          await response.pipe(source.openWrite());
          await verify(source, temporary);
        } finally {
          client.close(force: true);
          await temporary.delete(recursive: true);
        }
      },
      skip: baseUrl.isEmpty,
    );
  }
}
