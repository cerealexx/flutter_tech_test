import 'package:equatable/equatable.dart';

class AudioChunk {
  const AudioChunk({
    required this.path,
    required this.start,
    required this.end,
    required this.isLast,
    this.sourceDuration,
  });

  final String path;
  final Duration start;
  final Duration end;
  final bool isLast;
  final Duration? sourceDuration;
  Duration get duration => end - start;
}

class TranscriptSegment extends Equatable {
  const TranscriptSegment({
    required this.id,
    required this.text,
    required this.start,
    required this.end,
  });

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) =>
      TranscriptSegment(
        id: json['id'] as String,
        text: json['text'] as String,
        start: Duration(microseconds: json['startUs'] as int),
        end: Duration(microseconds: json['endUs'] as int),
      );

  final String id;
  final String text;
  final Duration start;
  final Duration end;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'startUs': start.inMicroseconds,
    'endUs': end.inMicroseconds,
  };

  @override
  List<Object?> get props => [id, text, start, end];
}

class KeyTopic extends Equatable {
  const KeyTopic({required this.title, required this.start});

  factory KeyTopic.fromJson(Map<String, dynamic> json) => KeyTopic(
    title: cleanTitle(json['title'] as String),
    start: Duration(microseconds: json['startUs'] as int),
  );

  final String title;
  final Duration start;

  static String cleanTitle(String title) =>
      title.trim().replaceFirst(RegExp(r'^\d+(?:_\d+)*\s+[-–—]\s+'), '').trim();

  Map<String, dynamic> toJson() => {
    'title': title,
    'startUs': start.inMicroseconds,
  };

  @override
  List<Object?> get props => [title, start];
}

class EpisodeInsights extends Equatable {
  const EpisodeInsights({required this.summary, required this.topics});

  factory EpisodeInsights.fromJson(Map<String, dynamic> json) =>
      EpisodeInsights(
        summary: json['summary'] as String,
        topics: (json['topics'] as List<dynamic>)
            .map((e) => KeyTopic.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  final String summary;
  final List<KeyTopic> topics;

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'topics': topics.map((e) => e.toJson()).toList(),
  };

  @override
  List<Object?> get props => [summary, topics];
}

enum EpisodeInsightsStatus {
  checkingCache,
  notConfigured,
  downloading,
  transcribing,
  summarizing,
  ready,
  error,
}

class InsightsProgress {
  const InsightsProgress(this.status, {this.fraction});
  final EpisodeInsightsStatus status;
  final double? fraction;
}

class InsightsResult {
  const InsightsResult({required this.insights, required this.audioUri});
  final EpisodeInsights insights;
  final Uri audioUri;
}
