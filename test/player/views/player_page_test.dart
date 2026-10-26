import 'dart:async';

import 'package:cabina/common/theme/app_theme.dart';
import 'package:cabina/episode_insights/cubit/episode_insights_cubit.dart';
import 'package:cabina/episode_insights/data/episode_insights_repository.dart';
import 'package:cabina/episode_insights/data/insights_cancellation.dart';
import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:cabina/player/bloc/audio_player_bloc.dart';
import 'package:cabina/player/data/audio_player_repository.dart';
import 'package:cabina/player/data/services/i_player_service.dart';
import 'package:cabina/player/models/player_args.dart';
import 'package:cabina/player/models/player_position.dart';
import 'package:cabina/player/models/player_status.dart';
import 'package:cabina/player/views/player_page.dart';
import 'package:cabina/show_detail/models/episode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../episode_insights/fakes.dart';

/// Keeps loading/playback pending so navigation races can be tested explicitly.
class _RoutePlayerService implements IPlayerService {
  final loading = Completer<Duration?>();
  final _playback = Completer<void>();
  final _statuses = StreamController<PlayerStatus>.broadcast(sync: true);

  int playCalls = 0;
  int disposeCalls = 0;
  bool isPlaying = false;

  @override
  Stream<PlayerPosition> get positionStream => const Stream.empty();

  @override
  Stream<PlayerStatus> get statusStream => _statuses.stream;

  @override
  Future<Duration?> open(String url) => loading.future;

  @override
  Future<void> play() {
    playCalls++;
    isPlaying = true;
    _statuses.add(PlayerStatus.playing);
    return _playback.future;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
    isPlaying = false;
    _playback.complete();
    await _statuses.close();
  }
}

class _RouteInsightsService extends DisabledInsightsService {
  final episodes = <String, PendingInsightsService>{};

  PendingInsightsService _forEpisode(Episode episode) =>
      episodes.putIfAbsent(episode.guid, PendingInsightsService.new);

  @override
  bool get configured => true;
  @override
  Future<InsightsResult> generate(
    Episode episode,
    InsightsCancellation cancellation,
    void Function(InsightsProgress) progress,
  ) => _forEpisode(episode).generate(episode, cancellation, progress);
}

void main() {
  for (final startPlayback in [false, true]) {
    testWidgets(
      'leaving ${startPlayback ? 'playing' : 'loading'} route releases its '
      'player and analysis and reopening owns new blocs',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const firstArgs = PlayerArgs(
          episode: Episode(
            guid: 'episode-1',
            title: 'First episode',
            audioUrl: 'https://example.com/first.mp3',
          ),
          podcastTitle: 'Podcast',
        );
        const secondArgs = PlayerArgs(
          episode: Episode(
            guid: 'episode-2',
            title: 'Second episode',
            audioUrl: 'https://example.com/second.mp3',
          ),
          podcastTitle: 'Podcast',
        );
        final services = <_RoutePlayerService>[];
        final insightsService = _RouteInsightsService();
        final insightsCubits = <EpisodeInsightsCubit>[];
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('Episodes')),
            ),
            GoRoute(
              path: PlayerPage.routePath,
              builder: (_, state) {
                final args = state.extra! as PlayerArgs;
                return MultiBlocProvider(
                  providers: [
                    BlocProvider(
                      create: (_) {
                        final service = _RoutePlayerService();
                        services.add(service);
                        return AudioPlayerBloc(
                          repository: AudioPlayerRepository(service: service),
                        );
                      },
                    ),
                    BlocProvider(
                      create: (context) {
                        final cubit = EpisodeInsightsCubit(
                          repository: context.read<EpisodeInsightsRepository>(),
                          episode: args.episode,
                        );
                        insightsCubits.add(cubit);
                        return cubit;
                      },
                    ),
                  ],
                  child: PlayerPage(args: args),
                );
              },
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          RepositoryProvider<EpisodeInsightsRepository>.value(
            value: EpisodeInsightsRepository(
              service: insightsService,
            ),
            child: MaterialApp.router(
              theme: AppTheme(isDark: false).toThemeData(),
              routerConfig: router,
            ),
          ),
        );

        unawaited(router.push<void>(PlayerPage.routePath, extra: firstArgs));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final first = services.single;
        final firstCubit = insightsCubits.single;
        final firstAnalysis = insightsService.episodes[firstArgs.episode.guid]!;
        expect(firstAnalysis.calls, 1);
        expect(
          tester.element(find.byType(PlayerPage)).read<EpisodeInsightsCubit>(),
          same(firstCubit),
        );
        if (startPlayback) {
          first.loading.complete(const Duration(minutes: 20));
          await tester.pumpAndSettle();
          expect(first.isPlaying, isTrue);
        } else {
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        }

        await tester.tap(find.byTooltip('Episode summary'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byTooltip('Close summary'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(firstAnalysis.calls, 1);
        expect(firstAnalysis.cancellation!.isCancelled, isFalse);
        expect(firstCubit.isClosed, isFalse);

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.byType(PlayerPage), findsNothing);
        expect(first.disposeCalls, 1);
        expect(first.isPlaying, isFalse);
        expect(firstCubit.isClosed, isTrue);
        expect(firstAnalysis.cancellation!.isCancelled, isTrue);

        unawaited(router.push<void>(PlayerPage.routePath, extra: secondArgs));
        await tester.pump();
        expect(services, hasLength(2));
        final second = services.last;
        final secondCubit = insightsCubits.last;
        final secondAnalysis =
            insightsService.episodes[secondArgs.episode.guid]!;
        expect(insightsCubits, hasLength(2));
        expect(secondCubit, isNot(same(firstCubit)));
        expect(secondAnalysis.calls, 1);
        second.loading.complete(const Duration(minutes: 10));
        await tester.pumpAndSettle();
        expect(find.text('Second episode'), findsOneWidget);
        expect(second.isPlaying, isTrue);

        final secondState = secondCubit.state;
        firstAnalysis.progress!(
          const InsightsProgress(
            EpisodeInsightsStatus.summarizing,
            fraction: 0.9,
          ),
        );
        firstAnalysis.completion.complete(
          InsightsResult(
            insights: const EpisodeInsights(summary: 'Late result', topics: []),
            audioUri: Uri.file('/tmp/first.mp3'),
          ),
        );
        await tester.pump();
        expect(secondCubit.state, secondState);

        if (!startPlayback) {
          // A late result from the previous route must not restart its audio.
          first.loading.complete(const Duration(minutes: 20));
          await tester.pump();
          expect(first.playCalls, 0);
        }
        expect(first.isPlaying, isFalse);
        expect(first.disposeCalls, 1);
        expect(second.disposeCalls, 0);

        // Replacing the route must release audio just like pressing Back.
        router.go('/');
        await tester.pumpAndSettle();
        expect(second.disposeCalls, 1);
        expect(second.isPlaying, isFalse);
        expect(secondCubit.isClosed, isTrue);
        expect(secondAnalysis.cancellation!.isCancelled, isTrue);
        secondAnalysis.completion.completeError(InsightsCancelled());
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
