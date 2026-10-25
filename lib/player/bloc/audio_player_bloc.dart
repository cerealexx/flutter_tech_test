import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/player/data/audio_player_repository.dart';
import 'package:cabina/player/models/playback_speed.dart';
import 'package:cabina/player/models/player_args.dart';
import 'package:cabina/player/models/player_position.dart';
import 'package:cabina/player/models/player_status.dart';
import 'package:equatable/equatable.dart';

part 'audio_player_event.dart';
part 'audio_player_state.dart';

class AudioPlayerBloc extends Bloc<AudioPlayerEvent, AudioPlayerState> {
  AudioPlayerBloc({required AudioPlayerRepository repository})
    : _repository = repository,
      super(const AudioPlayerState()) {
    on<PlayerOpened>(_whileActive(_onOpened));
    on<PlayerPlayPauseToggled>(_whileActive(_onPlayPauseToggled));
    on<PlayerSeeked>(_whileActive(_onSeeked));
    on<PlayerSpeedChanged>(_whileActive(_onSpeedChanged));
    on<PlayerPositionUpdated>(_onPositionUpdated);
    on<PlayerStatusUpdated>(_onStatusUpdated);

    _positionSub = _repository.positionStream.listen(
      (position) => _addIfActive(PlayerPositionUpdated(position)),
    );
    _statusSub = _repository.statusStream.listen(
      (status) => _addIfActive(PlayerStatusUpdated(status)),
    );
  }

  final AudioPlayerRepository _repository;

  late final StreamSubscription<PlayerPosition> _positionSub;
  late final StreamSubscription<PlayerStatus> _statusSub;

  bool _isClosing = false;

  void _addIfActive(AudioPlayerEvent event) {
    if (!_isClosing) add(event);
  }

  EventHandler<E, AudioPlayerState> _whileActive<E extends AudioPlayerEvent>(
    EventHandler<E, AudioPlayerState> handler,
  ) => (event, emit) async {
    if (_isClosing) return;
    try {
      await handler(event, emit);
    } catch (_) {
      if (!_isClosing) rethrow;
    }
  };

  Future<void> _onOpened(
    PlayerOpened event,
    Emitter<AudioPlayerState> emit,
  ) async {
    emit(state.copyWith(status: PlayerStatus.loading, args: event.args));
    try {
      final total = await _repository.open(event.args.episode.audioUrl);
      if (_isClosing || emit.isDone) return;
      emit(
        state.copyWith(
          position: PlayerPosition(total: total ?? event.args.episode.duration),
        ),
      );
      await _repository.play();
    } on CabinaException catch (e) {
      if (_isClosing || emit.isDone) return;
      emit(
        state.copyWith(
          status: PlayerStatus.error,
          errorMessage: e.message,
        ),
      );
    }
  }

  Future<void> _onPlayPauseToggled(
    PlayerPlayPauseToggled event,
    Emitter<AudioPlayerState> emit,
  ) async {
    if (state.status.isPlaying) {
      await _repository.pause();
    } else {
      await _repository.play();
    }
  }

  Future<void> _onSeeked(
    PlayerSeeked event,
    Emitter<AudioPlayerState> emit,
  ) async {
    await _repository.seekTo(event.position);
  }

  Future<void> _onSpeedChanged(
    PlayerSpeedChanged event,
    Emitter<AudioPlayerState> emit,
  ) async {
    await _repository.setSpeed(event.speed.value);
    if (_isClosing || emit.isDone) return;
    emit(state.copyWith(speed: event.speed));
  }

  void _onPositionUpdated(
    PlayerPositionUpdated event,
    Emitter<AudioPlayerState> emit,
  ) {
    if (_isClosing) return;
    final total = event.position.total ?? state.position.total;
    emit(
      state.copyWith(
        position: PlayerPosition(
          position: event.position.position,
          buffered: event.position.buffered,
          total: total,
        ),
      ),
    );
  }

  void _onStatusUpdated(
    PlayerStatusUpdated event,
    Emitter<AudioPlayerState> emit,
  ) {
    if (_isClosing) return;
    emit(state.copyWith(status: event.status));
  }

  @override
  Future<void> close() {
    _isClosing = true;

    return Future.wait<void>([
      _positionSub.cancel(),
      _statusSub.cancel(),
      _repository.dispose(),
      super.close(),
    ]);
  }
}
