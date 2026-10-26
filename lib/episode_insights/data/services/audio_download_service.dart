// Avoid synchronous file operations in the playback UI isolate.
// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:io';

import 'package:cabina/episode_insights/data/insights_cancellation.dart';
import 'package:http/http.dart' as http;

class AudioDownloadService {
  AudioDownloadService({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;

  Future<File> download({
    required Uri url,
    required Directory directory,
    required InsightsCancellation cancellation,
    required void Function(double?) onProgress,
  }) async {
    cancellation.check();
    if (url.scheme != 'https' && url.scheme != 'http') {
      throw const InsightsException(
        'This episode has an unsupported audio URL.',
      );
    }
    final client = _clientFactory();
    final unregister = cancellation.onCancel(client.close);
    final partial = File('${directory.path}/audio.part');
    IOSink? sink;
    try {
      // This client never receives the OpenAI Authorization header.
      final response = await cancellation.bind(
        client
            .send(http.Request('GET', url))
            .timeout(const Duration(seconds: 30)),
      );
      if (response.statusCode != 200) {
        throw const InsightsException(
          'The episode audio could not be downloaded.',
        );
      }
      sink = partial.openWrite();
      var received = 0;
      final header = <int>[];
      await for (final bytes in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        cancellation.check();
        if (header.length < 16) header.addAll(bytes.take(16 - header.length));
        sink.add(bytes);
        // Wait for disk writes instead of buffering the whole podcast.
        await sink.flush();
        received += bytes.length;
        final total = response.contentLength;
        onProgress(
          total == null || total == 0 ? null : (received / total).clamp(0, 1),
        );
      }
      await sink.close();
      sink = null;
      cancellation.check();
      if (received == 0 ||
          (response.contentLength != null &&
              response.contentLength != received)) {
        throw const InsightsException(
          'The audio download was incomplete. Please retry.',
        );
      }
      final extension = _extension(header);
      return await partial.rename('${directory.path}/audio.$extension');
    } on InsightsException {
      rethrow;
    } on InsightsCancelled {
      rethrow;
    } on Exception {
      cancellation.check();
      throw const InsightsException(
        'Could not download audio. Check your connection and storage.',
      );
    } finally {
      unregister();
      client.close();
      await sink?.close();
      if (await partial.exists()) await partial.delete();
    }
  }

  String _extension(List<int> header) {
    final signature = String.fromCharCodes(header);
    if (header.length >= 8 && signature.substring(4, 8) == 'ftyp') return 'm4a';
    if (signature.startsWith('RIFF')) return 'wav';
    if (signature.startsWith('OggS')) return 'ogg';
    if (signature.startsWith('fLaC')) return 'flac';
    if (signature.startsWith('ID3') ||
        (header.length >= 2 && header[0] == 255 && header[1] & 224 == 224)) {
      return 'mp3';
    }
    throw const InsightsException(
      'This audio format is not supported for analysis.',
    );
  }
}
