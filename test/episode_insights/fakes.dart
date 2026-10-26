import 'dart:async';

import 'package:cabina/episode_insights/data/insights_cancellation.dart';
import 'package:cabina/episode_insights/data/services/i_episode_insights_service.dart';
import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:cabina/show_detail/models/episode.dart';
import 'package:mocktail/mocktail.dart';

class DisabledInsightsService extends Fake implements IEpisodeInsightsService {
  @override
  bool get configured => false;
  @override
  Future<Uri?> cachedAudioUri(Episode episode) async => null;
  @override
  Future<InsightsResult> generate(
    Episode episode,
    InsightsCancellation cancellation,
    void Function(InsightsProgress) progress,
  ) async {
    throw const InsightsException('AI Companion is not configured.');
  }
}

class PendingInsightsService extends DisabledInsightsService {
  final completion = Completer<InsightsResult>();
  InsightsCancellation? cancellation;
  void Function(InsightsProgress)? progress;
  int calls = 0;
  @override
  bool get configured => true;
  @override
  Future<InsightsResult> generate(
    Episode episode,
    InsightsCancellation token,
    void Function(InsightsProgress) progress,
  ) {
    calls++;
    cancellation = token;
    this.progress = progress;
    return completion.future;
  }
}
