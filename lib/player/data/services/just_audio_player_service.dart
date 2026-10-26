import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/player/data/services/i_player_service.dart';
import 'package:cabina/player/models/player_position.dart';
import 'package:cabina/player/models/player_status.dart';
import 'package:just_audio/just_audio.dart';

class JustAudioPlayerService implements IPlayerService {
  JustAudioPlayerService({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<PlayerPosition> get positionStream => _player.positionStream.map(
    (position) => PlayerPosition(
      position: position,
      buffered: _player.bufferedPosition,
      total: _player.duration,
    ),
  );

  @override
  Stream<PlayerStatus> get statusStream =>
      _player.playerStateStream.map(_mapStatus);

  PlayerStatus _mapStatus(PlayerState state) {
    switch (state.processingState) {
      case ProcessingState.idle:
        return PlayerStatus.idle;
      case ProcessingState.loading:
        return PlayerStatus.loading;
      case ProcessingState.buffering:
        return PlayerStatus.buffering;
      case ProcessingState.ready:
        return state.playing ? PlayerStatus.playing : PlayerStatus.paused;
      case ProcessingState.completed:
        return PlayerStatus.completed;
    }
  }

  @override
  Future<Duration?> open(String url) => _perform(
    () => _player.setAudioSource(AudioSource.uri(Uri.parse(url))),
    'Could not load audio',
  );

  @override
  Future<void> play() => _perform(_player.play, 'Could not play audio');

  @override
  Future<void> pause() => _perform(_player.pause, 'Could not pause audio');

  @override
  Future<void> seekTo(Duration position) =>
      _perform(() => _player.seek(position), 'Could not seek audio');

  @override
  Future<void> setSpeed(double speed) => _perform(
    () => _player.setSpeed(speed),
    'Could not change playback speed',
  );

  @override
  Future<void> dispose() =>
      _perform(_player.dispose, 'Could not release audio');

  Future<T> _perform<T>(Future<T> Function() operation, String message) async {
    try {
      return await operation();
    } on Exception catch (error) {
      throw CabinaPlayerException(message, cause: error);
    }
  }
}
