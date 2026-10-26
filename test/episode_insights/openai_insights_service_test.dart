import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cabina/episode_insights/data/insights_cancellation.dart';
import 'package:cabina/episode_insights/data/services/audio_download_service.dart';
import 'package:cabina/episode_insights/data/services/openai_insights_service.dart';
import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('insights-api-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  const segment = TranscriptSegment(
    id: 's1',
    text: 'El futuro de la energía',
    start: Duration(seconds: 5),
    end: Duration(seconds: 20),
  );
  Map<String, dynamic> summary({String id = 's1'}) => {
    'summary': 'Hablamos sobre energía.',
    'topics': [
      {'title': 'Energía', 'segment_id': id},
    ],
  };
  http.Response response(Map<String, dynamic> payload) => http.Response(
    jsonEncode({
      'id': 'resp_test',
      'object': 'response',
      'created_at': 0,
      'status': 'completed',
      'output': [
        {
          'type': 'message',
          'id': 'msg_test',
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': jsonEncode(payload)},
          ],
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  http.Response transcriptionResponse(Map<String, dynamic> payload) {
    final segments = payload['segments'] as List<dynamic>;
    return http.Response(
      jsonEncode({
        'language': 'english',
        'duration': 120,
        'text': 'Transcript',
        ...payload,
        'segments': [
          for (var i = 0; i < segments.length; i++)
            {
              'id': i,
              'seek': 0,
              'tokens': <int>[],
              'temperature': 0,
              'avg_logprob': 0,
              'compression_ratio': 1,
              'no_speech_prob': 0,
              ...segments[i] as Map<String, dynamic>,
            },
        ],
      }),
      200,
    );
  }

  OpenAiInsightsService service(
    Future<http.Response> Function(http.Request) handler,
  ) => OpenAiInsightsService(
    apiKey: 'test-key',
    model: 'test-model',
    clientFactory: () => MockClient(handler),
    retryDelay: (_) async {},
  );

  test(
    'rebuilds multipart for five retries before accepting the sixth call',
    () async {
      final file = await File('${directory.path}/chunk.wav').writeAsBytes([
        82,
        73,
        70,
        70,
        1,
        2,
        3,
        4,
      ]);
      var calls = 0;
      final delays = <Duration>[];
      final api = OpenAiInsightsService(
        apiKey: 'test-key',
        model: 'test-model',
        retryDelay: (delay) async => delays.add(delay),
        clientFactory: () => MockClient((request) async {
          calls++;
          expect(request.headers['Authorization'], 'Bearer test-key');
          expect(request.body, contains('filename="episode.wav"'));
          expect(request.body, contains('RIFF'));
          expect(request.body, contains('whisper-1'));
          if (calls < 6) return http.Response('{}', 401);
          return transcriptionResponse({
            'segments': [
              {'start': 0, 'end': 1, 'text': 'A topic'},
            ],
          });
        }),
      );
      final result = await api.transcribe(
        AudioChunk(
          path: file.path,
          start: const Duration(seconds: 118),
          end: const Duration(seconds: 238),
          isLast: false,
        ),
        InsightsCancellation(),
      );
      expect(calls, 6);
      expect(delays.map((d) => d.inSeconds), [1, 2, 4, 8, 16]);
      expect(result.single.start, const Duration(seconds: 118));
    },
  );

  test('summary retries preserve the payload and bound Retry-After', () async {
    var calls = 0;
    String? originalBody;
    final delays = <Duration>[];
    final api = OpenAiInsightsService(
      apiKey: 'test-key',
      model: 'test-model',
      retryDelay: (delay) async => delays.add(delay),
      clientFactory: () => MockClient((request) async {
        calls++;
        originalBody ??= request.body;
        expect(request.body, originalBody);
        if (calls == 1) {
          return http.Response('{}', 429, headers: {'retry-after': '120'});
        }
        return response(summary());
      }),
    );
    await api.summarize([segment], InsightsCancellation());
    expect(calls, 2);
    expect(delays, [const Duration(seconds: 60)]);
  });

  test(
    'cancelling during backoff prevents further requests immediately',
    () async {
      var calls = 0;
      final waiting = Completer<void>();
      final delay = Completer<void>();
      final api = OpenAiInsightsService(
        apiKey: 'test-key',
        model: 'test-model',
        clientFactory: () => MockClient((_) async {
          calls++;
          return http.Response('{}', 403);
        }),
        retryDelay: (_) {
          waiting.complete();
          return delay.future;
        },
      );
      final cancellation = InsightsCancellation();
      final future = api.summarize([segment], cancellation);
      final assertion = expectLater(future, throwsA(isA<InsightsCancelled>()));
      await waiting.future;
      cancellation.cancel();
      await assertion;
      delay.complete();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
    },
  );

  test(
    'multipart requests real segment times and adds the chunk offset',
    () async {
      final file = await File(
        '${directory.path}/chunk.wav',
      ).writeAsBytes([82, 73, 70, 70]);
      final api = service((request) async {
        expect(request.url.path, '/v1/audio/transcriptions');
        expect(request.headers['Authorization'], 'Bearer test-key');
        expect(request.followRedirects, isFalse);
        expect(request.body, contains('whisper-1'));
        expect(request.body, contains('verbose_json'));
        expect(request.body, contains('timestamp_granularities[]'));
        expect(request.body, contains('filename="episode.wav"'));
        return transcriptionResponse({
          'segments': [
            {'start': 1.25, 'end': 3.5, 'text': ' Hello '},
          ],
        });
      });
      final result = await api.transcribe(
        AudioChunk(
          path: file.path,
          start: const Duration(seconds: 118),
          end: const Duration(seconds: 238),
          isLast: false,
        ),
        InsightsCancellation(),
      );
      expect(result.single.start, const Duration(milliseconds: 119250));
      expect(result.single.end, const Duration(milliseconds: 121500));
    },
  );

  test('clamps a trailing Whisper segment without moving its start', () async {
    final file = await File('${directory.path}/chunk.wav').writeAsBytes([0]);
    final api = service(
      (_) async => transcriptionResponse({
        'duration': 113.37000274658203,
        'segments': [
          {'start': 0, 'end': 2, 'text': 'Introduction'},
          {
            'start': 112.27999877929688,
            'end': 114.5999984741211,
            'text': 'Discussion continues at the chunk boundary',
          },
        ],
      }),
    );
    final result = await api.transcribe(
      AudioChunk(
        path: file.path,
        start: const Duration(microseconds: 46439),
        end: const Duration(microseconds: 113425078),
        isLast: false,
      ),
      InsightsCancellation(),
    );
    expect(result, hasLength(2));
    expect(result.first.end, const Duration(microseconds: 2046439));
    expect(result.last.start, const Duration(microseconds: 112326438));
    expect(result.last.end, const Duration(microseconds: 113425078));
  });

  test(
    'normalizes the captured part 11 boundary without shifting its topic',
    () async {
      final file = await File('${directory.path}/chunk.wav').writeAsBytes([0]);
      var transcriptionCalls = 0;
      final api = service((request) async {
        if (request.url.path == '/v1/responses') {
          return response(summary(id: '1114685147_1'));
        }
        transcriptionCalls++;
        return transcriptionResponse({
          'duration': 113.37000274658203,
          'segments': [
            {
              'start': 107.44000244140625,
              'end': 110.87999725341797,
              'text': 'Previous discussion',
            },
            {
              'start': 110.87999725341797,
              'end': 115.44000244140625,
              'text': 'Topic near the end of the fragment',
              'no_speech_prob': 0.3628973066806793,
            },
          ],
        });
      });
      final transcript = await api.transcribe(
        AudioChunk(
          path: file.path,
          start: const Duration(microseconds: 1114685147),
          end: const Duration(microseconds: 1228075373),
          isLast: false,
        ),
        InsightsCancellation(),
      );
      expect(transcriptionCalls, 1);
      expect(transcript, hasLength(2));
      expect(transcript.last.start, const Duration(microseconds: 1225565144));
      expect(transcript.last.end, const Duration(microseconds: 1228075373));
      final insights = await api.summarize(transcript, InsightsCancellation());
      expect(insights.topics.single.start, transcript.last.start);
    },
  );

  test('ignores the empty zero-length tail captured in Episode 12', () async {
    final file = await File('${directory.path}/chunk.wav').writeAsBytes([0]);
    final api = service(
      (_) async => transcriptionResponse({
        'duration': 113.37000274658203,
        'segments': [
          {
            'start': 111.31999969482422,
            'end': 112.31999969482422,
            'text': 'Previous discussion',
          },
          {
            'start': 112.31999969482422,
            'end': 113.31999969482422,
            'text': 'Last words',
          },
          {
            'start': 113.31999969482422,
            'end': 113.31999969482422,
            'text': '',
            'no_speech_prob': 5.307487663230859e-05,
          },
        ],
      }),
    );
    final result = await api.transcribe(
      AudioChunk(
        path: file.path,
        start: const Duration(microseconds: 334433697),
        end: const Duration(microseconds: 447820998),
        isLast: false,
      ),
      InsightsCancellation(),
    );
    expect(result, hasLength(2));
    expect(result.last.id, '334433697_1');
    expect(result.last.start, const Duration(microseconds: 446753697));
    expect(result.last.end, const Duration(microseconds: 447753697));
  });

  test('accepts the silent final fragment captured in Episode 12', () async {
    final file = await File('${directory.path}/chunk.wav').writeAsBytes([0]);
    var calls = 0;
    final api = service((_) async {
      calls++;
      return transcriptionResponse({
        'task': 'transcribe',
        'language': null,
        'duration': 20.030000686645508,
        'text': '',
        'segments': <dynamic>[],
        'usage': {'type': 'duration', 'seconds': 21},
      });
    });
    final result = await api.transcribe(
      AudioChunk(
        path: file.path,
        start: const Duration(microseconds: 1783394898),
        end: const Duration(microseconds: 1803520000),
        isLast: true,
      ),
      InsightsCancellation(),
    );
    expect(result, isEmpty);
    expect(calls, 1);
  });

  test('null language preserves speech and its timestamp validation', () async {
    final file = await File('${directory.path}/chunk.wav').writeAsBytes([0]);
    for (final end in [2, 400]) {
      final api = service(
        (_) async => transcriptionResponse({
          'language': null,
          'segments': [
            {'start': 1, 'end': end, 'text': 'Speech without a language'},
          ],
        }),
      );
      final result = api.transcribe(
        AudioChunk(
          path: file.path,
          start: const Duration(seconds: 118),
          end: const Duration(seconds: 238),
          isLast: false,
        ),
        InsightsCancellation(),
      );
      if (end == 2) {
        final segments = await result;
        expect(segments.single.text, 'Speech without a language');
        expect(segments.single.start, const Duration(seconds: 119));
        expect(segments.single.end, const Duration(seconds: 120));
      } else {
        await expectLater(result, throwsA(isA<InsightsException>()));
      }
    }
  });

  test('rejects timestamps outside the actual audio fragment', () async {
    final file = await File('${directory.path}/chunk.wav').writeAsBytes([0]);
    for (final (start, end) in [
      (0, 400),
      (9, 15.001),
      (10, 10.1),
      (10.1, 10.2),
      (-0.1, 1),
      (5, 5),
      (5, 4),
    ]) {
      final api = service(
        (_) async => transcriptionResponse({
          'segments': [
            {'start': start, 'end': end, 'text': 'Wrong'},
          ],
        }),
      );
      await expectLater(
        api.transcribe(
          AudioChunk(
            path: file.path,
            start: Duration.zero,
            end: const Duration(seconds: 10),
            isLast: true,
          ),
          InsightsCancellation(),
        ),
        throwsA(isA<InsightsException>()),
      );
    }
  });

  test('bounds final-segment normalization at five seconds', () async {
    final file = await File('${directory.path}/chunk.wav').writeAsBytes([0]);
    final api = service(
      (_) async => transcriptionResponse({
        'segments': [
          {'start': 9, 'end': 15, 'text': 'Final segment'},
        ],
      }),
    );
    final result = await api.transcribe(
      AudioChunk(
        path: file.path,
        start: const Duration(seconds: 118),
        end: const Duration(seconds: 128),
        isLast: true,
      ),
      InsightsCancellation(),
    );
    expect(result.single.start, const Duration(seconds: 127));
    expect(result.single.end, const Duration(seconds: 128));
  });

  test('does not apply the trailing tolerance to earlier segments', () async {
    final file = await File('${directory.path}/chunk.wav').writeAsBytes([0]);
    final api = service(
      (_) async => transcriptionResponse({
        'segments': [
          {'start': 8, 'end': 11, 'text': 'Invalid non-final segment'},
          {'start': 9, 'end': 10, 'text': 'Last segment'},
        ],
      }),
    );
    await expectLater(
      api.transcribe(
        AudioChunk(
          path: file.path,
          start: Duration.zero,
          end: const Duration(seconds: 10),
          isLast: true,
        ),
        InsightsCancellation(),
      ),
      throwsA(isA<InsightsException>()),
    );
  });

  test(
    'uses strict schema and resolves topics from existing segment IDs',
    () async {
      final api = service((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.url.path, '/v1/responses');
        expect(request.followRedirects, isFalse);
        expect(request.headers['Authorization'], 'Bearer test-key');
        expect(body['model'], 'test-model');
        expect(body['store'], isFalse);
        expect(body['max_output_tokens'], 6000);
        expect(
          (body['text'] as Map<String, dynamic>)['format'],
          containsPair('strict', true),
        );
        expect(body['input'], contains('s1'));
        return response(summary());
      });
      final result = await api.summarize([segment], InsightsCancellation());
      expect(result.topics.single.start, const Duration(seconds: 5));
    },
  );

  test('rejects invented segment references', () async {
    final api = service((_) async => response(summary(id: 'invented')));
    await expectLater(
      api.summarize([segment], InsightsCancellation()),
      throwsA(isA<InsightsException>()),
    );
  });

  for (final status in [302, 400, 401, 403, 409, 429, 500, 503]) {
    test(
      'maps HTTP $status without exposing response bodies or credentials',
      () async {
        var calls = 0;
        final api = service((_) async {
          calls++;
          return http.Response('secret-server-detail', status);
        });
        await expectLater(
          api.summarize([segment], InsightsCancellation()),
          throwsA(
            isA<InsightsException>().having(
              (e) => e.message,
              'safe message',
              allOf(isNot(contains('secret')), isNot(contains('OpenAI'))),
            ),
          ),
        );
        expect(calls, 6);
      },
    );
  }

  test(
    'generated titles omit segment IDs and keep their resolved times',
    () async {
      final api = service(
        (_) async => response({
          'summary': 'A summary',
          'topics': [
            {
              'title': '46439_0 — Host banter and farm-life opening',
              'segment_id': 's1',
            },
          ],
        }),
      );
      final result = await api.summarize([segment], InsightsCancellation());
      expect(result.topics.single.title, 'Host banter and farm-life opening');
      expect(result.topics.single.start, segment.start);
    },
  );

  test('incomplete output and refusals are not cached as summaries', () async {
    for (final payload in [
      {'status': 'incomplete', 'output': <dynamic>[]},
      {
        'status': 'completed',
        'output': [
          {
            'type': 'message',
            'id': 'msg_test',
            'role': 'assistant',
            'content': [
              {'type': 'refusal', 'refusal': 'No'},
            ],
          },
        ],
      },
    ]) {
      final api = service(
        (_) async => http.Response(
          jsonEncode({
            'id': 'resp_test',
            'object': 'response',
            'created_at': 0,
            ...payload,
          }),
          200,
        ),
      );
      await expectLater(
        api.summarize([segment], InsightsCancellation()),
        throwsA(
          isA<InsightsException>().having(
            (e) => e.message,
            'message',
            'Our system did not return a complete summary. Please retry.',
          ),
        ),
      );
    }
  });

  test('silence makes no summary request', () async {
    var calls = 0;
    final api = service((_) async {
      calls++;
      return response(summary());
    });
    await expectLater(
      api.summarize([], InsightsCancellation()),
      throwsA(isA<InsightsException>()),
    );
    expect(calls, 0);
  });

  test(
    'long transcripts include every segment and reduce partial summaries',
    () async {
      final segments = List.generate(
        5,
        (i) => TranscriptSegment(
          id: 's$i',
          text: 'word ' * 5000,
          start: Duration(seconds: i * 30),
          end: Duration(seconds: i * 30 + 20),
        ),
      );
      var calls = 0;
      final seen = <String>{};
      final api = service((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final input = body['input'] as String;
        expect(input.length, lessThanOrEqualTo(40000));
        final records = jsonDecode(input) as List<dynamic>;
        for (final raw in records) {
          final row = raw as Map<String, dynamic>;
          if (row['id'] case final String id) seen.add(id);
        }
        final first = records.first as Map<String, dynamic>;
        return response(summary(id: (first['id'] as String?) ?? 's0'));
      });
      await api.summarize(segments, InsightsCancellation());
      expect(seen, {'s0', 's1', 's2', 's3', 's4'});
      expect(calls, 6);
    },
  );

  test(
    'cancellation completes without waiting for a late HTTP result',
    () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final api = service((_) {
        started.complete();
        return pending.future;
      });
      final cancellation = InsightsCancellation();
      final future = api.summarize([segment], cancellation);
      final assertion = expectLater(future, throwsA(isA<InsightsCancelled>()));
      await started.future;
      cancellation.cancel();
      await assertion;
      pending.complete(response(summary()));
    },
  );

  test(
    'audio download never sends an OpenAI key and detects content format',
    () async {
      final downloader = AudioDownloadService(
        clientFactory: () => MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response.bytes([73, 68, 51, ...List.filled(200, 0)], 200);
        }),
      );
      final file = await downloader.download(
        url: Uri.parse('https://example.com/no-extension'),
        directory: directory,
        cancellation: InsightsCancellation(),
        onProgress: (_) {},
      );
      expect(file.path, endsWith('audio.mp3'));
      expect(File('${directory.path}/audio.part').existsSync(), isFalse);
    },
  );

  test('honors numeric Retry-After for every rejected HTTP status', () async {
    for (final (status, header, seconds) in [
      (302, '3', 3),
      (401, '2', 2),
      (429, '120', 60),
      (500, '0', 1),
      (503, '-5', 1),
      (503, 'invalid', 1),
    ]) {
      var calls = 0;
      final delays = <Duration>[];
      final api = OpenAiInsightsService(
        apiKey: 'test-key',
        model: 'test-model',
        retryDelay: (delay) async => delays.add(delay),
        clientFactory: () => MockClient((request) async {
          calls++;
          expect(request.url.host, 'api.openai.com');
          expect(request.followRedirects, isFalse);
          if (calls == 1) {
            return http.Response(
              '{}',
              status,
              headers: {
                'retry-after': header,
                'location': 'https://example.com/redirect',
              },
            );
          }
          return response(summary());
        }),
      );
      await api.summarize([segment], InsightsCancellation());
      expect(calls, 2);
      expect(delays, [Duration(seconds: seconds)]);
    }
  });

  test('malformed SDK responses fail safely without HTTP retries', () async {
    for (final body in ['not json', '[]', '{"id": 123}']) {
      var calls = 0;
      final api = service((_) async {
        calls++;
        return http.Response(body, 200);
      });
      await expectLater(
        api.summarize([segment], InsightsCancellation()),
        throwsA(
          isA<InsightsException>().having(
            (e) => e.message,
            'message',
            'The analysis service returned an unreadable response.',
          ),
        ),
      );
      expect(calls, 1);
    }
  });

  test(
    'network failures are not replayed and release the HTTP client',
    () async {
      for (final error in [
        const SocketException('private network detail'),
        TimeoutException('private timeout detail'),
        http.ClientException('private transport detail'),
      ]) {
        var calls = 0;
        final client = _TrackingClient((_) async {
          calls++;
          throw error;
        });
        final api = OpenAiInsightsService(
          apiKey: 'test-key',
          model: 'test-model',
          clientFactory: () => client,
        );
        await expectLater(
          api.summarize([segment], InsightsCancellation()),
          throwsA(
            isA<InsightsException>().having(
              (e) => e.message,
              'message',
              'The analysis request failed. Check your connection and retry.',
            ),
          ),
        );
        expect(calls, 1);
        expect(client.closed, isTrue);
      }
    },
  );

  test(
    'cancels an upload, closes HTTP and ignores a late malformed body',
    () async {
      final file = await File('${directory.path}/chunk.wav').writeAsBytes([0]);
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      var calls = 0;
      final client = _TrackingClient((_) {
        calls++;
        started.complete();
        return pending.future;
      });
      final api = OpenAiInsightsService(
        apiKey: 'test-key',
        model: 'test-model',
        clientFactory: () => client,
      );
      final cancellation = InsightsCancellation();
      final future = api.transcribe(
        AudioChunk(
          path: file.path,
          start: Duration.zero,
          end: const Duration(seconds: 10),
          isLast: true,
        ),
        cancellation,
      );
      final assertion = expectLater(future, throwsA(isA<InsightsCancelled>()));
      await started.future;
      cancellation.cancel();
      await assertion;
      expect(client.closed, isTrue);
      pending.complete(http.Response('malformed', 200));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
    },
  );

  test(
    'transcription filters silence and preserves IDs and ordering',
    () async {
      final file = await File('${directory.path}/chunk.wav').writeAsBytes([0]);
      final api = service(
        (_) async => transcriptionResponse({
          'segments': [
            {'start': 4, 'end': 5, 'text': 'Later'},
            {'start': 0, 'end': 1, 'text': 'Noise', 'no_speech_prob': 0.9},
            {'start': 1, 'end': 2, 'text': ' '},
            {'start': 2, 'end': 3, 'text': ' Earlier '},
          ],
        }),
      );
      final result = await api.transcribe(
        AudioChunk(
          path: file.path,
          start: const Duration(seconds: 118),
          end: const Duration(seconds: 128),
          isLast: true,
        ),
        InsightsCancellation(),
      );
      expect(result.map((s) => s.text), ['Earlier', 'Later']);
      expect(result.map((s) => s.id), ['118000000_1', '118000000_0']);
      expect(result.first.start, const Duration(seconds: 120));
    },
  );

  test('missing key makes no HTTP request', () async {
    final api = OpenAiInsightsService(
      apiKey: ' ',
      model: 'test-model',
      clientFactory: () => throw StateError('No client should be created'),
    );
    await expectLater(
      api.summarize([segment], InsightsCancellation()),
      throwsA(
        isA<InsightsException>().having(
          (e) => e.message,
          'message',
          'AI Companion is not configured.',
        ),
      ),
    );
  });
}

class _TrackingClient extends MockClient {
  _TrackingClient(super.fn);

  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}
