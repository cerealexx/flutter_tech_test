import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/library/data/library_repository.dart';
import 'package:cabina/library/models/subscribed_podcast.dart';
import 'package:equatable/equatable.dart';

part 'library_state.dart';

class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit({required LibraryRepository repository})
    : _repository = repository,
      super(LibraryState()) {
    unawaited(load());
  }

  final LibraryRepository _repository;

  Future<void> load() async {
    if (state.status == LibraryStatus.loading ||
        state.status == LibraryStatus.ready) {
      return;
    }

    emit(LibraryState(status: LibraryStatus.loading));

    try {
      final items = await _repository.load();
      emit(
        LibraryState(
          status: LibraryStatus.ready,
          items: items,
        ),
      );
    } on CabinaException catch (error) {
      emit(
        LibraryState(
          status: LibraryStatus.error,
          errorMessage: error.message,
        ),
      );
    }
  }

  Future<void> subscribe(SubscribedPodcast podcast) async {
    final previousState = state;

    emit(state.copyWith(items: [...state.items, podcast]));

    try {
      await _repository.subscribe(podcast);
    } on CabinaException catch (error) {
      emit(
        previousState.copyWith(
          errorMessage: error.message,
          failedPodcastId: podcast.id,
        ),
      );
    }
  }

  Future<void> unsubscribe(int id) async {
    final previousState = state;

    emit(
      state.copyWith(
        items: state.items.where((item) => item.id != id).toList(),
      ),
    );

    try {
      await _repository.unsubscribe(id);
    } on CabinaException catch (error) {
      emit(
        previousState.copyWith(
          errorMessage: error.message,
          failedPodcastId: id,
        ),
      );
    }
  }
}
