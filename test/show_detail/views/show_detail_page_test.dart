import 'package:cabina/app/widgets/app_dependency_injection.dart';
import 'package:cabina/common/network/api_client.dart';
import 'package:cabina/common/theme/app_theme.dart';
import 'package:cabina/discover/models/podcast.dart';
import 'package:cabina/show_detail/bloc/show_detail_bloc.dart';
import 'package:cabina/show_detail/data/show_detail_repository.dart';
import 'package:cabina/show_detail/views/show_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApiClient extends Mock implements ApiClient {}

void main() {
  testWidgets('invalid RSS structure shows its feed error and can recover', (
    tester,
  ) async {
    const podcast = Podcast(
      id: 1503869154,
      title: 'The Top Chef After Show Podcast',
      author: 'AfterBuzz TV',
      feedUrl: 'https://example.com/feed.xml',
    );
    final feedUri = Uri.parse(podcast.feedUrl);
    final apiClient = _MockApiClient();
    // Valid XML can still lack the required RSS structure.
    when(() => apiClient.getString(feedUri)).thenAnswer((_) async => '<rss />');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      AppDependencyInjection(
        prefs: prefs,
        apiClient: apiClient,
        child: MaterialApp(
          theme: AppTheme(isDark: false).toThemeData(),
          home: BlocProvider(
            create: (context) => ShowDetailBloc(
              repository: context.read<ShowDetailRepository>(),
            ),
            child: const ShowDetailPage(podcast: podcast),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('Feed is missing a channel'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    when(() => apiClient.getString(feedUri)).thenAnswer(
      (_) async => '''
<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <item>
      <guid>episode-1</guid>
      <title>Top Chef recap</title>
      <enclosure url="https://example.com/episode.mp3" type="audio/mpeg" />
      <itunes:duration>3173</itunes:duration>
    </item>
  </channel>
</rss>
''',
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Top Chef recap'), findsOneWidget);
    expect(find.text('52m'), findsOneWidget);
    verify(() => apiClient.getString(feedUri)).called(2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
