import 'package:bloc/bloc.dart';
import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/discover/models/podcast.dart';
import 'package:cabina/show_detail/data/show_detail_repository.dart';
import 'package:cabina/show_detail/models/podcast_detail.dart';
import 'package:equatable/equatable.dart';

part 'show_detail_event.dart';
part 'show_detail_state.dart';

class ShowDetailBloc extends Bloc<ShowDetailEvent, ShowDetailState> {
  ShowDetailBloc({required ShowDetailRepository repository})
    : _repository = repository,
      super(const ShowDetailState()) {
    on<ShowDetailRequested>(_onRequested);
  }

  final ShowDetailRepository _repository;

  Future<void> _onRequested(
    ShowDetailRequested event,
    Emitter<ShowDetailState> emit,
  ) async {
    emit(const ShowDetailState(status: ShowDetailStatus.loading));
    try {
      final detail = await _repository.loadDetail(event.podcast);
      emit(ShowDetailState(status: ShowDetailStatus.ready, detail: detail));
    } on CabinaException catch (e) {
      emit(
        ShowDetailState(
          status: ShowDetailStatus.error,
          errorMessage: e.message,
        ),
      );
    }
  }
}
