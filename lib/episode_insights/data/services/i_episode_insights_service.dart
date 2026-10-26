import 'package:cabina/episode_insights/data/insights_cancellation.dart';
import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:cabina/show_detail/models/episode.dart';

abstract class IEpisodeInsightsService {
  bool get configured;

  Future<Uri?> cachedAudioUri(Episode episode);

  /// Reuses a completed result or resumes analysis from its saved checkpoint.
  Future<InsightsResult> generate(
    Episode episode,
    InsightsCancellation cancellation,
    void Function(InsightsProgress) progress,
  );
}
