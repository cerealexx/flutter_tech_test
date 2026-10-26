part of 'audio_player_bloc.dart';

sealed class AudioPlayerEvent extends Equatable {
  const AudioPlayerEvent();

  @override
  List<Object?> get props => [];
}

class PlayerOpened extends AudioPlayerEvent {
  const PlayerOpened(this.args, {this.sourceUri});

  final PlayerArgs args;
  final Uri? sourceUri;

  @override
  List<Object?> get props => [args, sourceUri];
}

class PlayerTopicSelected extends AudioPlayerEvent {
  const PlayerTopicSelected({required this.position, required this.audioUri});
  final Duration position;
  final Uri audioUri;
  @override
  List<Object?> get props => [position, audioUri];
}

class PlayerPlayPauseToggled extends AudioPlayerEvent {
  const PlayerPlayPauseToggled();
}

class PlayerSeeked extends AudioPlayerEvent {
  const PlayerSeeked(this.position);

  final Duration position;

  @override
  List<Object?> get props => [position];
}

class PlayerSpeedChanged extends AudioPlayerEvent {
  const PlayerSpeedChanged(this.speed);

  final PlaybackSpeed speed;

  @override
  List<Object?> get props => [speed];
}

class PlayerPositionUpdated extends AudioPlayerEvent {
  const PlayerPositionUpdated(this.position);

  final PlayerPosition position;

  @override
  List<Object?> get props => [position];
}

class PlayerStatusUpdated extends AudioPlayerEvent {
  const PlayerStatusUpdated(this.status);

  final PlayerStatus status;

  @override
  List<Object?> get props => [status];
}
