import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/player/bloc/audio_player_bloc.dart';
import 'package:cabina/player/data/audio_player_repository.dart';
import 'package:cabina/player/data/services/i_player_service.dart';
import 'package:cabina/player/models/playback_speed.dart';
import 'package:cabina/player/models/player_args.dart';
import 'package:cabina/player/models/player_position.dart';
import 'package:cabina/player/models/player_status.dart';
import 'package:cabina/show_detail/models/episode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlayerService extends Mock implements IPlayerService {}

void main() {
  const args = PlayerArgs(
    episode: Episode(
      guid: 'episode-1',
      title: 'Episode',
      audioUrl: 'https://example.com/episode.mp3',
    ),
    podcastTitle: 'Podcast',
  );
  late _MockPlayerService service;
  late StreamController<PlayerPosition> positions;
  late StreamController<PlayerStatus> statuses;

  setUp(() {
    service = _MockPlayerService();
    positions = StreamController<PlayerPosition>(sync: true);
    statuses = StreamController<PlayerStatus>(sync: true);
    when(() => service.positionStream).thenAnswer((_) => positions.stream);
    when(() => service.statusStream).thenAnswer((_) => statuses.stream);
    when(service.dispose).thenAnswer((_) async {});
    when(() => service.open(args.episode.audioUrl)).thenAnswer(
      (_) async => const Duration(minutes: 20),
    );
    when(service.play).thenAnswer((_) async {});
  });

  tearDown(() async {
    await positions.close();
    await statuses.close();
  });

  for (final status in [PlayerStatus.playing, PlayerStatus.paused]) {
    test(
      'rapid seeks from $status wait for the preceding native seek',
      () async {
        final bloc = AudioPlayerBloc(
          repository: AudioPlayerRepository(service: service),
        );
        addTearDown(bloc.close);
        final firstSeek = Completer<void>();
        const first = Duration(minutes: 5);
        const last = Duration(minutes: 15);
        when(() => service.seekTo(first)).thenAnswer((_) => firstSeek.future);
        when(() => service.seekTo(last)).thenAnswer((_) async {});
        statuses.add(status);
        await pumpEventQueue();

        bloc
          ..add(const PlayerSeeked(first))
          ..add(const PlayerSeeked(last));
        await pumpEventQueue();
        verify(() => service.seekTo(first)).called(1);
        verifyNever(() => service.seekTo(last));

        firstSeek.complete();
        await pumpEventQueue();
        verify(() => service.seekTo(last)).called(1);
        expect(bloc.state.status, status);
        verifyNever(service.play);
        verifyNever(service.pause);
      },
    );
  }

  group('completed playback', () {
    late AudioPlayerBloc bloc;
    const total = Duration(minutes: 20);

    setUp(() {
      bloc = AudioPlayerBloc(
        repository: AudioPlayerRepository(service: service),
      );
    });

    tearDown(() async {
      if (!bloc.isClosed) await bloc.close();
    });

    test('resets progress and ignores late end-position updates', () async {
      positions.add(
        const PlayerPosition(position: total, buffered: total, total: total),
      );
      statuses.add(PlayerStatus.playing);
      await pumpEventQueue();
      expect(bloc.state.position.progress, 1);

      statuses.add(PlayerStatus.completed);
      await pumpEventQueue();
      expect(bloc.state.status, PlayerStatus.completed);
      expect(
        bloc.state.position,
        const PlayerPosition(buffered: total, total: total),
      );

      // Position and status arrive on separate streams, in either order.
      positions.add(const PlayerPosition(position: total, buffered: total));
      await pumpEventQueue();
      expect(bloc.state.position.position, Duration.zero);
      expect(bloc.state.position.total, total);
      verifyNever(service.play);
    });

    test('play after each completion rewinds before starting again', () async {
      for (var replay = 0; replay < 2; replay++) {
        statuses.add(PlayerStatus.completed);
        await pumpEventQueue();
        final seeking = Completer<void>();
        when(() => service.seekTo(Duration.zero)).thenAnswer(
          (_) => seeking.future,
        );
        when(service.play).thenAnswer((_) async {
          statuses.add(PlayerStatus.playing);
        });

        bloc.add(const PlayerPlayPauseToggled());
        await pumpEventQueue();
        verify(() => service.seekTo(Duration.zero)).called(1);
        verifyNever(service.play);

        seeking.complete();
        await pumpEventQueue();
        verify(service.play).called(1);
        expect(bloc.state.status, PlayerStatus.playing);
        positions.add(
          const PlayerPosition(position: Duration(seconds: 1), total: total),
        );
        await pumpEventQueue();
        expect(bloc.state.position.position, const Duration(seconds: 1));
      }
    });

    test('resuming a paused episode keeps its current position', () async {
      positions.add(
        const PlayerPosition(position: Duration(minutes: 3), total: total),
      );
      statuses.add(PlayerStatus.paused);
      await pumpEventQueue();

      bloc.add(const PlayerPlayPauseToggled());
      await pumpEventQueue();

      verify(service.play).called(1);
      verifyNever(() => service.seekTo(Duration.zero));
      expect(bloc.state.position.position, const Duration(minutes: 3));
    });

    test('leaving during rewind cannot restart playback', () async {
      final seeking = Completer<void>();
      final started = Completer<void>();
      when(() => service.seekTo(Duration.zero)).thenAnswer((_) {
        started.complete();
        return seeking.future;
      });
      statuses.add(PlayerStatus.completed);
      await pumpEventQueue();
      bloc.add(const PlayerPlayPauseToggled());
      await started.future;

      await bloc.close();
      seeking.complete();
      await pumpEventQueue();

      verifyNever(service.play);
    });
  });

  group('lifecycle', () {
    late AudioPlayerBloc bloc;

    setUp(() {
      bloc = AudioPlayerBloc(
        repository: AudioPlayerRepository(service: service),
      );
    });

    tearDown(() async {
      if (!bloc.isClosed) await bloc.close();
    });

    test('close releases its player and cancels both subscriptions', () async {
      await bloc.close();

      verify(service.dispose).called(1);
      expect(positions.hasListener, isFalse);
      expect(statuses.hasListener, isFalse);
      expect(bloc.isClosed, isTrue);
    });

    test('close waits for player disposal to finish', () async {
      final disposal = Completer<void>();
      when(service.dispose).thenAnswer((_) => disposal.future);
      var closed = false;

      final closing = bloc.close();
      unawaited(closing.then((_) => closed = true));
      await pumpEventQueue();
      expect(closed, isFalse);

      disposal.complete();
      await closing;
      expect(closed, isTrue);
      verify(service.dispose).called(1);
    });

    test('disposes without waiting for subscription cancellation', () async {
      final cancellation = Completer<void>();
      positions.onCancel = () {
        // The status listener is still attached while cancellation starts.
        statuses.add(PlayerStatus.playing);
        return cancellation.future;
      };

      final closing = bloc.close();
      verify(service.dispose).called(1);
      await pumpEventQueue();
      expect(bloc.state, const AudioPlayerState());

      cancellation.complete();
      await closing;
    });

    test('queued events cannot use the player once closing starts', () async {
      bloc
        ..add(const PlayerOpened(args))
        ..add(const PlayerPlayPauseToggled())
        ..add(const PlayerSeeked(Duration(seconds: 30)))
        ..add(const PlayerSpeedChanged(PlaybackSpeed.x2));
      positions.add(const PlayerPosition(position: Duration(seconds: 5)));
      statuses.add(PlayerStatus.playing);

      await bloc.close();
      // Late stream notifications must not add events to the closed bloc.
      positions.add(const PlayerPosition(position: Duration(seconds: 10)));
      statuses.add(PlayerStatus.completed);
      await pumpEventQueue();

      expect(bloc.state, const AudioPlayerState());
      verifyNever(() => service.open(args.episode.audioUrl));
      verifyNever(service.play);
      verifyNever(() => service.seekTo(const Duration(seconds: 30)));
      verifyNever(() => service.setSpeed(2));
    });

    for (final completeAfterClose in [false, true]) {
      for (final failLoad in [false, true]) {
        test(
          'load ${failLoad ? 'failure' : 'success'} '
          '${completeAfterClose ? 'after' : 'during'} close cannot autoplay '
          'or emit a state',
          () async {
            final loading = Completer<Duration?>();
            final loadStarted = Completer<void>();
            final disposal = Completer<void>();
            when(() => service.open(args.episode.audioUrl)).thenAnswer((_) {
              loadStarted.complete();
              return loading.future;
            });
            when(service.dispose).thenAnswer((_) => disposal.future);
            bloc.add(const PlayerOpened(args));
            await loadStarted.future;
            final lastState = bloc.state;

            final closing = bloc.close();
            if (completeAfterClose) {
              disposal.complete();
              // Closing must not wait for the pending load.
              await closing;
            }
            if (failLoad) {
              loading.completeError(const CabinaPlayerException('Interrupted'));
            } else {
              loading.complete(const Duration(minutes: 20));
            }
            await pumpEventQueue();

            expect(bloc.state, lastState);
            verifyNever(service.play);
            if (!completeAfterClose) disposal.complete();
            await closing;
            verify(service.dispose).called(1);
          },
        );
      }
    }

    test('close releases an actively playing episode', () async {
      final playback = Completer<void>();
      final started = Completer<void>();
      var playing = false;
      when(service.play).thenAnswer((_) {
        playing = true;
        statuses.add(PlayerStatus.playing);
        started.complete();
        return playback.future;
      });
      when(service.dispose).thenAnswer((_) async {
        playing = false;
        playback.complete();
      });
      bloc.add(const PlayerOpened(args));
      await started.future;
      expect(playing, isTrue);

      await bloc.close();

      expect(playing, isFalse);
      verify(service.dispose).called(1);
      expect(bloc.isClosed, isTrue);
    });

    for (final operation in ['autoplay', 'play', 'pause', 'seek', 'speed']) {
      test('pending $operation errors after close are ignored', () async {
        final command = Completer<void>();
        final started = Completer<void>();
        Future<void> pending() {
          started.complete();
          return command.future;
        }

        switch (operation) {
          case 'autoplay':
            when(service.play).thenAnswer((_) => pending());
            bloc.add(const PlayerOpened(args));
          case 'play':
            when(service.play).thenAnswer((_) => pending());
            bloc.add(const PlayerPlayPauseToggled());
          case 'pause':
            final playing = bloc.stream.firstWhere(
              (state) => state.status == PlayerStatus.playing,
            );
            statuses.add(PlayerStatus.playing);
            await playing;
            when(service.pause).thenAnswer((_) => pending());
            bloc.add(const PlayerPlayPauseToggled());
          case 'seek':
            when(() => service.seekTo(const Duration(seconds: 30))).thenAnswer(
              (_) => pending(),
            );
            bloc.add(const PlayerSeeked(Duration(seconds: 30)));
          case 'speed':
            when(() => service.setSpeed(2)).thenAnswer((_) => pending());
            bloc.add(const PlayerSpeedChanged(PlaybackSpeed.x2));
        }
        await started.future;

        await bloc.close();
        final lastState = bloc.state;
        command.completeError(const CabinaPlayerException('Player disposed'));
        await pumpEventQueue();

        expect(bloc.state, lastState);
        expect(bloc.isClosed, isTrue);
      });
    }

    test('speed completion during close does not emit a state', () async {
      final speed = Completer<void>();
      final started = Completer<void>();
      final disposal = Completer<void>();
      when(() => service.setSpeed(2)).thenAnswer((_) {
        started.complete();
        return speed.future;
      });
      when(service.dispose).thenAnswer((_) => disposal.future);
      bloc.add(const PlayerSpeedChanged(PlaybackSpeed.x2));
      await started.future;

      final closing = bloc.close();
      speed.complete();
      await pumpEventQueue();
      expect(bloc.state.speed, PlaybackSpeed.x1);

      disposal.complete();
      await closing;
    });

    test(
      'disposal failure still closes the bloc and cancels listeners',
      () async {
        when(service.dispose).thenAnswer((_) async {
          throw StateError('Disposal failed');
        });

        await expectLater(bloc.close(), throwsStateError);

        expect(bloc.isClosed, isTrue);
        expect(positions.hasListener, isFalse);
        expect(statuses.hasListener, isFalse);
        verify(service.dispose).called(1);
      },
    );
  });

  for (final status in [
    PlayerStatus.paused,
    PlayerStatus.playing,
    PlayerStatus.completed,
  ]) {
    test(
      'topic from $status switches to analyzed audio, seeks, then plays',
      () async {
        final local = Uri.file('/tmp/analyzed.mp3');
        when(service.pause).thenAnswer((_) async {});
        when(
          () => service.open(local.toString()),
        ).thenAnswer((_) async => const Duration(minutes: 10));
        when(() => service.setSpeed(1.5)).thenAnswer((_) async {});
        when(
          () => service.seekTo(const Duration(seconds: 65)),
        ).thenAnswer((_) async {});
        final bloc = AudioPlayerBloc(
          repository: AudioPlayerRepository(service: service),
        )..add(const PlayerSpeedChanged(PlaybackSpeed.x1_5));
        await pumpEventQueue();
        verify(() => service.setSpeed(1.5)).called(1);
        statuses.add(status);
        await pumpEventQueue();
        bloc.add(
          PlayerTopicSelected(
            position: const Duration(seconds: 65),
            audioUri: local,
          ),
        );
        await pumpEventQueue();
        verifyInOrder([
          service.pause,
          () => service.open(local.toString()),
          () => service.setSpeed(1.5),
          () => service.seekTo(const Duration(seconds: 65)),
          service.play,
        ]);
        expect(bloc.state.speed, PlaybackSpeed.x1_5);
        // A second tap on the same analyzed source must not reload it.
        bloc.add(
          PlayerTopicSelected(
            position: const Duration(seconds: 65),
            audioUri: local,
          ),
        );
        await pumpEventQueue();
        verifyNever(() => service.open(local.toString()));
        verify(() => service.seekTo(const Duration(seconds: 65))).called(1);
        await bloc.close();
      },
    );
  }

  test('leaving during topic load cannot seek or restart playback', () async {
    final local = Uri.file('/tmp/analyzed.mp3');
    final loading = Completer<Duration?>();
    final started = Completer<void>();
    when(service.pause).thenAnswer((_) async {});
    when(() => service.open(local.toString())).thenAnswer((_) {
      started.complete();
      return loading.future;
    });
    final bloc =
        AudioPlayerBloc(
          repository: AudioPlayerRepository(service: service),
        )..add(
          PlayerTopicSelected(
            position: const Duration(seconds: 65),
            audioUri: local,
          ),
        );
    await started.future;
    await bloc.close();
    loading.complete(const Duration(minutes: 10));
    await pumpEventQueue();
    verifyNever(() => service.seekTo(const Duration(seconds: 65)));
    verifyNever(service.play);
  });

  blocTest<AudioPlayerBloc, AudioPlayerState>(
    'normal load failures still reach the UI',
    build: () {
      when(() => service.open(args.episode.audioUrl)).thenThrow(
        const CabinaPlayerException('Cannot load audio'),
      );
      return AudioPlayerBloc(
        repository: AudioPlayerRepository(service: service),
      );
    },
    act: (bloc) => bloc.add(const PlayerOpened(args)),
    expect: () => [
      const AudioPlayerState(status: PlayerStatus.loading, args: args),
      const AudioPlayerState(
        status: PlayerStatus.error,
        args: args,
        errorMessage: 'Cannot load audio',
      ),
    ],
  );

  blocTest<AudioPlayerBloc, AudioPlayerState>(
    'normal command failures are not suppressed',
    build: () {
      when(service.play).thenThrow(StateError('Playback failed'));
      return AudioPlayerBloc(
        repository: AudioPlayerRepository(service: service),
      );
    },
    act: (bloc) => bloc.add(const PlayerPlayPauseToggled()),
    errors: () => [isA<StateError>()],
  );
}
