import 'package:cabina/episode_insights/data/insights_cancellation.dart';
import 'package:cabina/episode_insights/data/services/i_episode_insights_service.dart';
import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:cabina/show_detail/models/episode.dart';

class EpisodeInsightsRepository {
  EpisodeInsightsRepository({required IEpisodeInsightsService service})
    : _service = service;

  final IEpisodeInsightsService _service;

  bool get configured => _service.configured;

  Future<Uri?> cachedAudioUri(Episode episode) =>
      _service.cachedAudioUri(episode);

  Future<InsightsResult> generate(
    Episode episode,
    InsightsCancellation cancellation,
    void Function(InsightsProgress) progress,
  ) => _service.generate(episode, cancellation, progress);
}
