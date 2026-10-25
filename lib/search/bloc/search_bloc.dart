import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/discover/models/podcast.dart';
import 'package:cabina/search/data/search_repository.dart';
import 'package:equatable/equatable.dart';

part 'search_event.dart';
part 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc({required SearchRepository searchRepository})
    : _searchRepository = searchRepository,
      super(const SearchState()) {
    on<SearchTermChanged>(_onTermChanged, transformer: restartable());
  }

  final SearchRepository _searchRepository;

  Future<void> _onTermChanged(
    SearchTermChanged event,
    Emitter<SearchState> emit,
  ) async {
    final query = event.term.trim();
    if (query.isEmpty) {
      emit(const SearchState());
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (emit.isDone) return;

    emit(state.copyWith(status: SearchStatus.loading, query: query));
    try {
      final results = await _searchRepository.search(query);
      if (emit.isDone) return;
      emit(state.copyWith(status: SearchStatus.ready, results: results));
    } on CabinaException catch (e) {
      if (emit.isDone) return;
      emit(state.copyWith(status: SearchStatus.error, errorMessage: e.message));
    }
  }
}
