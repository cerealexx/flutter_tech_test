import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/player/data/services/just_audio_player_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';

class _Player extends Mock implements AudioPlayer {}

void main() {
  setUpAll(
    () => registerFallbackValue(AudioSource.uri(Uri.file('/tmp/audio.mp3'))),
  );

  for (final operation in [
    'open',
    'play',
    'pause',
    'seek',
    'speed',
    'dispose',
  ]) {
    test(
      '$operation translates platform failures into player exceptions',
      () async {
        final player = _Player();
        final service = JustAudioPlayerService(player: player);
        final failure = PlatformException(code: 'audio_unavailable');
        late Future<void> Function() execute;
        switch (operation) {
          case 'open':
            when(() => player.setAudioSource(any())).thenThrow(failure);
            execute = () async {
              await service.open('file:///tmp/audio.mp3');
            };
          case 'play':
            when(player.play).thenThrow(failure);
            execute = service.play;
          case 'pause':
            when(player.pause).thenThrow(failure);
            execute = service.pause;
          case 'seek':
            when(() => player.seek(Duration.zero)).thenThrow(failure);
            execute = () => service.seekTo(Duration.zero);
          case 'speed':
            when(() => player.setSpeed(1.5)).thenThrow(failure);
            execute = () => service.setSpeed(1.5);
          case 'dispose':
            when(player.dispose).thenThrow(failure);
            execute = service.dispose;
        }
        await expectLater(
          execute(),
          throwsA(
            isA<CabinaPlayerException>().having(
              (e) => e.cause,
              'cause',
              same(failure),
            ),
          ),
        );
      },
    );
  }

  test('programming errors are not presented as player failures', () async {
    final player = _Player();
    when(player.play).thenThrow(StateError('Bug in the audio adapter'));
    final service = JustAudioPlayerService(player: player);
    await expectLater(service.play(), throwsStateError);
  });
}
