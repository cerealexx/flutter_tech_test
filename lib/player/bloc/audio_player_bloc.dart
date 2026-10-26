import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
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
    on<PlayerSeeked>(_whileActive(_onSeeked), transformer: sequential());
    on<PlayerTopicSelected>(
      _whileActive(_onTopicSelected),
      transformer: sequential(),
    );
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
  // Releases the sequential topic handler when the user leaves during a load.
  final _closingSignal = Completer<void>();
  Uri? _sourceUri;
  // An older opening must not overwrite a more recent topic selection.
  int _sourceRevision = 0;

  void _addIfActive(AudioPlayerEvent event) {
    if (!_isClosing) add(event);
  }

  EventHandler<E, AudioPlayerState> _whileActive<E extends AudioPlayerEvent>(
    EventHandler<E, AudioPlayerState> handler,
  ) => (event, emit) async {
    if (_isClosing) return;
    try {
      await Future.any<void>([
        Future<void>.sync(() => handler(event, emit)),
        _closingSignal.future,
      ]);
    } on Exception {
      if (!_isClosing) rethrow;
    }
  };

  Future<void> _onOpened(
    PlayerOpened event,
    Emitter<AudioPlayerState> emit,
  ) async {
    emit(state.copyWith(status: PlayerStatus.loading, args: event.args));
    final revision = ++_sourceRevision;
    final source = event.sourceUri ?? Uri.parse(event.args.episode.audioUrl);
    try {
      final total = await _repository.open(source.toString());
      if (_isClosing || revision != _sourceRevision) return;
      _sourceUri = source;
      emit(
        state.copyWith(
          position: PlayerPosition(total: total ?? event.args.episode.duration),
        ),
      );
      await _repository.play();
    } on CabinaPlayerException catch (e) {
      if (_isClosing || revision != _sourceRevision) return;
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
      if (state.status == PlayerStatus.completed) {
        await _repository.seekTo(Duration.zero);
        if (_isClosing) return;
      }
      await _repository.play();
    }
  }

  Future<void> _onSeeked(
    PlayerSeeked event,
    Emitter<AudioPlayerState> emit,
  ) async {
    await _repository.seekTo(event.position);
  }

  Future<void> _onTopicSelected(
    PlayerTopicSelected event,
    Emitter<AudioPlayerState> emit,
  ) async {
    ++_sourceRevision;
    try {
      if (_sourceUri != event.audioUri) {
        // Pause before replacing the source so it cannot briefly play at zero.
        await _repository.pause();
        if (_isClosing) return;
        final total = await _repository.open(event.audioUri.toString());
        if (_isClosing) return;
        _sourceUri = event.audioUri;
        emit(state.copyWith(position: PlayerPosition(total: total)));
        await _repository.setSpeed(state.speed.value);
      }

      if (_isClosing) return;
      final total = state.position.total;
      if (total != null && event.position >= total) return;
      await _repository.seekTo(event.position);
      if (_isClosing) return;

      // just_audio's play future lasts until playback finishes. Do not block
      // subsequent topic taps behind that future.
      unawaited(
        _repository.play().onError<CabinaPlayerException>((_, _) {
          _addIfActive(const PlayerStatusUpdated(PlayerStatus.error));
        }),
      );
    } on CabinaPlayerException {
      if (!_isClosing) {
        emit(
          state.copyWith(
            status: PlayerStatus.error,
            errorMessage: 'Could not play the selected topic',
          ),
        );
      }
    }
  }

  Future<void> _onSpeedChanged(
    PlayerSpeedChanged event,
    Emitter<AudioPlayerState> emit,
  ) async {
    await _repository.setSpeed(event.speed.value);
    if (_isClosing) return;
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
          // A final position event can arrive after the completed status.
          position: state.status == PlayerStatus.completed
              ? Duration.zero
              : event.position.position,
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
    emit(
      state.copyWith(
        status: event.status,
        position: event.status == PlayerStatus.completed
            ? PlayerPosition(
                buffered: state.position.buffered,
                total: state.position.total,
              )
            : null,
      ),
    );
  }

  @override
  Future<void> close() {
    _isClosing = true;
    if (!_closingSignal.isCompleted) _closingSignal.complete();

    return Future.wait<void>([
      _positionSub.cancel(),
      _statusSub.cancel(),
      _repository.dispose(),
      super.close(),
    ]);
  }
}
