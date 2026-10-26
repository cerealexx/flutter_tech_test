import 'package:cabina/common/theme/app_theme.dart';
import 'package:cabina/episode_insights/cubit/episode_insights_cubit.dart';
import 'package:cabina/episode_insights/data/episode_insights_repository.dart';
import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:cabina/episode_insights/widgets/episode_insights_drawer.dart';
import 'package:cabina/show_detail/models/episode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'drawer opens without interrupting generation and topics expose '
    'source and time',
    (tester) async {
      const episode = Episode(
        guid: '1',
        title: 'Episode title',
        audioUrl: 'https://example.com/a.mp3',
      );
      final service = PendingInsightsService();
      final cubit = EpisodeInsightsCubit(
        repository: EpisodeInsightsRepository(service: service),
        episode: episode,
      );
      final started = cubit.generate();
      addTearDown(cubit.close);
      final scaffold = GlobalKey<ScaffoldState>();
      KeyTopic? selected;
      Uri? source;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme(isDark: false).toThemeData(),
          home: Scaffold(
            key: scaffold,
            endDrawer: EpisodeInsightsDrawer(
              title: episode.title,
              cubit: cubit,
              onTopic: (topic, uri) {
                selected = topic;
                source = uri;
                scaffold.currentState!.closeEndDrawer();
              },
            ),
            body: const Text('Player'),
          ),
        ),
      );
      scaffold.currentState!.openEndDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Checking saved analysis…'), findsOneWidget);
      service.progress!(
        const InsightsProgress(
          EpisodeInsightsStatus.transcribing,
          fraction: 0.42,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Generating summary... 42%'), findsOneWidget);
      expect(find.text('Retry analysis'), findsNothing);
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, 0.42);
      expect(indicator.semanticsValue, '42%');
      expect(
        find.text(
          'You can keep listening while our system analyzes the episode.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('OpenAI'), findsNothing);
      service.progress!(
        const InsightsProgress(
          EpisodeInsightsStatus.summarizing,
          fraction: 0.9,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Generating summary... 90%'), findsOneWidget);
      await tester.tap(find.byTooltip('Close summary'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.cancellation!.isCancelled, isFalse);
      service.completion.complete(
        InsightsResult(
          audioUri: Uri.file('/tmp/analyzed.mp3'),
          insights: const EpisodeInsights(
            summary: 'A useful summary',
            topics: [
              KeyTopic(
                title: 'First topic',
                start: Duration(seconds: 65),
              ),
              KeyTopic(
                title: 'Later topic',
                start: Duration(hours: 1, seconds: 5),
              ),
            ],
          ),
        ),
      );
      await started;
      expect(cubit.state.progressPercent, 100);
      scaffold.currentState!.openEndDrawer();
      await tester.pumpAndSettle();
      expect(find.text('A useful summary'), findsOneWidget);
      expect(find.text('1:05'), findsOneWidget);
      expect(find.text('1:00:05'), findsOneWidget);
      await tester.tap(find.text('First topic'));
      await tester.pumpAndSettle();
      expect(selected!.start, const Duration(seconds: 65));
      expect(source, Uri.file('/tmp/analyzed.mp3'));
      expect(scaffold.currentState!.isEndDrawerOpen, isFalse);
      expect(service.calls, 1);
    },
  );
}
