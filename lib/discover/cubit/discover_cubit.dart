import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/discover/data/discover_repository.dart';
import 'package:cabina/discover/data/favourites_repository.dart';
import 'package:cabina/discover/models/podcast.dart';
import 'package:equatable/equatable.dart';

part 'discover_state.dart';

class DiscoverCubit extends Cubit<DiscoverState> {
  DiscoverCubit({
    required DiscoverRepository discoverRepository,
    required FavouritesRepository favouritesRepository,
  })  : _discoverRepository = discoverRepository,
        _favouritesRepository = favouritesRepository,
        super(const DiscoverState()) {
    _restoreFavourites();
  }

  final DiscoverRepository _discoverRepository;
  final FavouritesRepository _favouritesRepository;

  void _restoreFavourites() {
    emit(state.copyWith(favouriteIds: _favouritesRepository.load()));
  }

  Future<void> loadFeatured() async {
    emit(state.copyWith(status: DiscoverStatus.loading));
    try {
      final podcasts = await _discoverRepository.featured();
      emit(state.copyWith(
        status: DiscoverStatus.ready,
        podcasts: podcasts,
      ));
    } on CabinaException catch (e) {
      emit(
        state.copyWith(
          status: DiscoverStatus.error,
          errorMessage: e.message,
        ),
      );
    }
  }

  void toggleFavourite(int podcastId) {
    final favourites = [...state.favouriteIds];
    if (favourites.contains(podcastId)) {
      favourites.remove(podcastId);
    } else {
      favourites.add(podcastId);
    }
    emit(state.copyWith(favouriteIds: favourites));
    unawaited(_favouritesRepository.save(favourites));
  }
}
