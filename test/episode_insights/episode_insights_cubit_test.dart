import 'package:cabina/episode_insights/cubit/episode_insights_cubit.dart';
import 'package:cabina/episode_insights/data/episode_insights_repository.dart';
import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:cabina/show_detail/models/episode.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  const episode = Episode(
    guid: '1',
    title: 'Episode',
    audioUrl: 'https://example.com/a.mp3',
  );

  test(
    'starts once and cancellation ignores late progress and completion',
    () async {
      final service = PendingInsightsService();
      final cubit = EpisodeInsightsCubit(
        repository: EpisodeInsightsRepository(service: service),
        episode: episode,
      );
      final started = cubit.generate();
      await cubit.generate();
      expect(service.calls, 1);
      service.progress!(
        const InsightsProgress(
          EpisodeInsightsStatus.transcribing,
          fraction: 0.5,
        ),
      );
      expect(cubit.state.progressPercent, 50);
      await cubit.close();
      expect(service.cancellation!.isCancelled, isTrue);
      service.progress!(
        const InsightsProgress(EpisodeInsightsStatus.summarizing),
      );
      service.completion.complete(
        InsightsResult(
          insights: const EpisodeInsights(summary: 'Late', topics: []),
          audioUri: Uri.file('/tmp/episode.mp3'),
        ),
      );
      await started;
      expect(cubit.state.progressPercent, 50);
    },
  );

  test('missing key is a non-fatal not-configured state', () async {
    final cubit = EpisodeInsightsCubit(
      repository: EpisodeInsightsRepository(service: DisabledInsightsService()),
      episode: episode,
    );
    await cubit.generate();
    expect(cubit.state.status, EpisodeInsightsStatus.notConfigured);
    await cubit.close();
  });
}
