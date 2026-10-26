import 'dart:async';
import 'dart:io';

import 'package:cabina/episode_insights/data/insights_cancellation.dart';
import 'package:cabina/episode_insights/data/services/audio_download_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _StreamingClient extends http.BaseClient {
  final body = StreamController<List<int>>();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(body.stream, 200);

  @override
  void close() {
    if (closed) return;
    closed = true;
    body.addError(http.ClientException('Connection closed'));
    unawaited(body.close());
  }
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('audio-download-');
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'cancelling a streamed download closes HTTP and removes the partial file',
    () async {
      final client = _StreamingClient();
      client.body.onListen = () => client.body.add([73, 68, 51, 0]);
      final cancellation = InsightsCancellation();
      final received = Completer<void>();
      final download = AudioDownloadService(clientFactory: () => client)
          .download(
            url: Uri.parse('https://example.com/episode.mp3'),
            directory: directory,
            cancellation: cancellation,
            onProgress: (_) => received.complete(),
          );
      final result = expectLater(download, throwsA(isA<InsightsCancelled>()));
      await received.future;
      cancellation.cancel();
      await result;
      expect(client.closed, isTrue);
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test('an incomplete response is never saved as playable audio', () async {
    final service = AudioDownloadService(
      clientFactory: () => MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.value([73, 68, 51, 0]),
          200,
          contentLength: 10,
        ),
      ),
    );
    await expectLater(
      service.download(
        url: Uri.parse('https://example.com/episode.mp3'),
        directory: directory,
        cancellation: InsightsCancellation(),
        onProgress: (_) {},
      ),
      throwsA(isA<InsightsException>()),
    );
    expect(await directory.list().toList(), isEmpty);
  });
}
