// JSON field types come from external data; only parsing catches TypeError.
// ignore_for_file: avoid_catching_errors

// These filesystem checks run off the UI thread's synchronous execution path.
// ignore_for_file: avoid_slow_async_io

import 'dart:convert';
import 'dart:io';

import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:cabina/show_detail/models/episode.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class CachedEpisode {
  CachedEpisode(this.directory);
  final Directory directory;
  String? audioName;
  Duration nextStart = Duration.zero;
  Duration duration = Duration.zero;
  Duration? sourceDuration;
  bool transcribed = false;
  List<TranscriptSegment> segments = [];
  EpisodeInsights? insights;
  String? summaryModel;

  File? get audio =>
      audioName == null ? null : File('${directory.path}/$audioName');

  Map<String, dynamic> toJson() => {
    'version': InsightsCacheService.version,
    'audioName': audioName,
    'nextStartUs': nextStart.inMicroseconds,
    'durationUs': duration.inMicroseconds,
    'sourceDurationUs': sourceDuration?.inMicroseconds,
    'transcribed': transcribed,
    'segments': segments.map((e) => e.toJson()).toList(),
    'insights': insights?.toJson(),
    'summaryModel': summaryModel,
  };
}

class InsightsCacheService {
  InsightsCacheService({
    Future<Directory> Function()? root,
  }) : _root = root ?? _defaultRoot;

  // Increment when chunking, transcript merging, or prompt contracts change.
  static const version = 1;
  final Future<Directory> Function() _root;

  static Future<Directory> _defaultRoot() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/episode_insights',
  );

  String key(Episode episode) => sha256
      .convert(
        utf8.encode(
          jsonEncode([episode.guid, episode.audioUrl, version]),
        ),
      )
      .toString();

  Future<CachedEpisode> open(Episode episode) async {
    final directory = Directory('${(await _root()).path}/${key(episode)}');
    await directory.create(recursive: true);
    final entry = CachedEpisode(directory);
    final manifest = File('${directory.path}/manifest.json');

    if (!await manifest.exists()) return entry;

    try {
      final json =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;

      if (json['version'] != version) return entry;

      final name = json['audioName'] as String?;

      if (name == null || !RegExp(r'^audio\.[a-z0-9]+$').hasMatch(name)) {
        return entry;
      }

      final audio = File('${directory.path}/$name');

      if (!await audio.exists() || await audio.length() == 0) {
        // A missing download cannot be used for playback or resuming analysis.
        return entry;
      }

      entry
        ..audioName = name
        ..nextStart = Duration(microseconds: json['nextStartUs'] as int)
        ..duration = Duration(microseconds: json['durationUs'] as int)
        ..sourceDuration = switch (json['sourceDurationUs']) {
          final int us when us > 0 => Duration(microseconds: us),
          _ => null,
        }
        ..transcribed = json['transcribed'] as bool
        ..segments = (json['segments'] as List<dynamic>)
            .map((e) => TranscriptSegment.fromJson(e as Map<String, dynamic>))
            .toList()
        ..summaryModel = json['summaryModel'] as String?
        ..insights = json['insights'] == null
            ? null
            : EpisodeInsights.fromJson(
                json['insights'] as Map<String, dynamic>,
              );
      return entry;
    } on FileSystemException {
      return CachedEpisode(directory);
    } on FormatException {
      return CachedEpisode(directory);
    } on TypeError {
      // Old or malformed JSON is treated as a cache miss.
      return CachedEpisode(directory);
    }
  }

  Future<void> save(CachedEpisode entry) async {
    final temporary = File('${entry.directory.path}/manifest.tmp');
    await temporary.writeAsString(jsonEncode(entry.toJson()), flush: true);
    await temporary.rename('${entry.directory.path}/manifest.json');
  }
}
