part of 'episode_insights_cubit.dart';

class EpisodeInsightsState extends Equatable {
  const EpisodeInsightsState({
    this.status = EpisodeInsightsStatus.checkingCache,
    this.fraction,
    this.result,
    this.errorMessage,
  });

  final EpisodeInsightsStatus status;
  final double? fraction;
  final InsightsResult? result;
  final String? errorMessage;

  int get progressPercent => ((fraction ?? 0).clamp(0, 1) * 100).floor();

  bool get isBusy => switch (status) {
    EpisodeInsightsStatus.checkingCache ||
    EpisodeInsightsStatus.downloading ||
    EpisodeInsightsStatus.transcribing ||
    EpisodeInsightsStatus.summarizing => true,
    _ => false,
  };

  @override
  List<Object?> get props => [status, fraction, result, errorMessage];
}
