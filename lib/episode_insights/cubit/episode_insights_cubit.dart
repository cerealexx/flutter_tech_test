import 'package:cabina/episode_insights/data/episode_insights_repository.dart';
import 'package:cabina/episode_insights/data/insights_cancellation.dart';
import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:cabina/show_detail/models/episode.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'episode_insights_state.dart';

class EpisodeInsightsCubit extends Cubit<EpisodeInsightsState> {
  EpisodeInsightsCubit({required this.repository, required this.episode})
    : super(const EpisodeInsightsState());
  final EpisodeInsightsRepository repository;
  final Episode episode;
  InsightsCancellation? _cancellation;
  bool _started = false;

  Future<void> generate() async {
    if (_started || isClosed) return;
    _started = true;
    final cancellation = InsightsCancellation();
    _cancellation = cancellation;

    emit(const EpisodeInsightsState());

    try {
      final result = await repository.generate(episode, cancellation, (
        progress,
      ) {
        if (!isClosed) {
          emit(
            EpisodeInsightsState(
              status: progress.status,
              fraction: progress.fraction,
            ),
          );
        }
      });
      if (!isClosed) {
        emit(
          EpisodeInsightsState(
            status: EpisodeInsightsStatus.ready,
            fraction: 1,
            result: result,
          ),
        );
      }
    } on InsightsCancelled {
      // Route disposal intentionally stops further network and native work.
    } on Exception catch (error) {
      if (isClosed) return;
      emit(
        EpisodeInsightsState(
          status: repository.configured
              ? EpisodeInsightsStatus.error
              : EpisodeInsightsStatus.notConfigured,
          errorMessage: error is InsightsException
              ? error.message
              : 'Could not analyze this episode. '
                    'Check your connection and available storage.',
        ),
      );
    }
  }

  Future<void> retry() async {
    if (state.status != EpisodeInsightsStatus.error) return;
    _started = false;
    await generate();
  }

  @override
  Future<void> close() {
    _cancellation?.cancel();
    return super.close();
  }
}
