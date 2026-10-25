import 'dart:async';

import 'package:cabina/common/theme/app_theme.dart';
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

void main() {
  for (final startPlayback in [false, true]) {
    testWidgets(
      'leaving ${startPlayback ? 'playing' : 'loading'} route releases its '
      'player and reopening owns a new player',
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
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('Episodes')),
            ),
            GoRoute(
              path: PlayerPage.routePath,
              builder: (_, state) => BlocProvider(
                create: (_) {
                  final service = _RoutePlayerService();
                  services.add(service);
                  return AudioPlayerBloc(
                    repository: AudioPlayerRepository(service: service),
                  );
                },
                child: PlayerPage(args: state.extra! as PlayerArgs),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            theme: AppTheme(isDark: false).toThemeData(),
            routerConfig: router,
          ),
        );

        unawaited(router.push<void>(PlayerPage.routePath, extra: firstArgs));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final first = services.single;
        if (startPlayback) {
          first.loading.complete(const Duration(minutes: 20));
          await tester.pumpAndSettle();
          expect(first.isPlaying, isTrue);
        } else {
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        }

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.byType(PlayerPage), findsNothing);
        expect(first.disposeCalls, 1);
        expect(first.isPlaying, isFalse);

        unawaited(router.push<void>(PlayerPage.routePath, extra: secondArgs));
        await tester.pump();
        expect(services, hasLength(2));
        final second = services.last;
        second.loading.complete(const Duration(minutes: 10));
        await tester.pumpAndSettle();
        expect(find.text('Second episode'), findsOneWidget);
        expect(second.isPlaying, isTrue);

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
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
