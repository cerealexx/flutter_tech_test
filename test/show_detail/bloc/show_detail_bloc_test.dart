import 'package:bloc_test/bloc_test.dart';
import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/discover/models/podcast.dart';
import 'package:cabina/show_detail/bloc/show_detail_bloc.dart';
import 'package:cabina/show_detail/data/show_detail_repository.dart';
import 'package:cabina/show_detail/models/podcast_detail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockShowDetailRepository extends Mock implements ShowDetailRepository {}

void main() {
  late _MockShowDetailRepository repository;
  const podcast = Podcast(
    id: 1,
    title: 'Test podcast',
    author: 'Author',
    feedUrl: 'https://example.com/feed.xml',
  );
  const detail = PodcastDetail(
    podcastId: 1,
    title: 'Test podcast',
    author: 'Author',
    episodes: [],
  );

  setUp(() => repository = _MockShowDetailRepository());

  ShowDetailBloc buildBloc() => ShowDetailBloc(repository: repository);

  blocTest<ShowDetailBloc, ShowDetailState>(
    'loads the detail',
    build: () {
      when(
        () => repository.loadDetail(podcast),
      ).thenAnswer((_) async => detail);
      return buildBloc();
    },
    act: (bloc) => bloc.add(const ShowDetailRequested(podcast)),
    expect: () => [
      const ShowDetailState(status: ShowDetailStatus.loading),
      const ShowDetailState(status: ShowDetailStatus.ready, detail: detail),
    ],
  );

  for (final error in [
    const NetworkException('Offline'),
    const FeedParseException('Invalid feed'),
  ]) {
    blocTest<ShowDetailBloc, ShowDetailState>(
      'shows the message for ${error.runtimeType}',
      build: () {
        when(() => repository.loadDetail(podcast)).thenThrow(error);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const ShowDetailRequested(podcast)),
      expect: () => [
        const ShowDetailState(status: ShowDetailStatus.loading),
        ShowDetailState(
          status: ShowDetailStatus.error,
          errorMessage: error.message,
        ),
      ],
    );
  }

  blocTest<ShowDetailBloc, ShowDetailState>(
    'retry succeeds and clears the previous error',
    build: () {
      when(() => repository.loadDetail(podcast)).thenThrow(
        const NetworkException('Offline'),
      );
      return buildBloc();
    },
    act: (bloc) async {
      final failed = bloc.stream.firstWhere(
        (state) => state.status == ShowDetailStatus.error,
      );
      bloc.add(const ShowDetailRequested(podcast));
      await failed;
      when(
        () => repository.loadDetail(podcast),
      ).thenAnswer((_) async => detail);
      bloc.add(const ShowDetailRequested(podcast));
    },
    expect: () => [
      const ShowDetailState(status: ShowDetailStatus.loading),
      const ShowDetailState(
        status: ShowDetailStatus.error,
        errorMessage: 'Offline',
      ),
      const ShowDetailState(status: ShowDetailStatus.loading),
      const ShowDetailState(status: ShowDetailStatus.ready, detail: detail),
    ],
  );
}
