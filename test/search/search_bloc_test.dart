import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/discover/models/podcast.dart';
import 'package:cabina/search/bloc/search_bloc.dart';
import 'package:cabina/search/data/search_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSearchRepository extends Mock implements SearchRepository {}

void main() {
  late _MockSearchRepository repository;

  const podcast = Podcast(
    id: 1,
    title: 'Reply All',
    author: 'Gimlet',
    feedUrl: 'https://example.com/feed.xml',
  );

  // Allow the debounce and asynchronous search handler to settle.
  const settle = Duration(milliseconds: 400);

  setUp(() => repository = _MockSearchRepository());

  SearchBloc buildBloc() => SearchBloc(searchRepository: repository);

  group('SearchBloc', () {
    blocTest<SearchBloc, SearchState>(
      'emits [loading, ready] with results for a non-empty query',
      build: () {
        when(() => repository.search(any())).thenAnswer((_) async => [podcast]);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const SearchTermChanged('reply all')),
      wait: settle,
      expect: () => [
        const SearchState(status: SearchStatus.loading, query: 'reply all'),
        const SearchState(
          status: SearchStatus.ready,
          query: 'reply all',
          results: [podcast],
        ),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'resets to initial state for an empty query',
      build: buildBloc,
      seed: () => const SearchState(
        status: SearchStatus.ready,
        query: 'old',
        results: [podcast],
      ),
      act: (bloc) => bloc.add(const SearchTermChanged('   ')),
      wait: settle,
      expect: () => [const SearchState()],
    );

    blocTest<SearchBloc, SearchState>(
      'emits [error] when the repository throws a CabinaException',
      build: () {
        when(
          () => repository.search(any()),
        ).thenThrow(const NetworkException('offline'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const SearchTermChanged('reply')),
      wait: settle,
      expect: () => [
        const SearchState(status: SearchStatus.loading, query: 'reply'),
        const SearchState(
          status: SearchStatus.error,
          query: 'reply',
          errorMessage: 'offline',
        ),
      ],
    );

    test('searches only after 300 ms without typing', () async {
      when(() => repository.search(any())).thenAnswer((_) async => [podcast]);
      final bloc = buildBloc();
      addTearDown(bloc.close);
      final ready = bloc.stream
          .firstWhere((state) => state.status == SearchStatus.ready)
          .timeout(const Duration(seconds: 2));

      bloc.add(const SearchTermChanged('rep'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      bloc.add(const SearchTermChanged('reply'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      bloc.add(const SearchTermChanged('  reply all  '));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      verifyZeroInteractions(repository);
      expect(bloc.state, const SearchState());

      await ready;

      verify(() => repository.search('reply all')).called(1);
      verifyNoMoreInteractions(repository);
      expect(
        bloc.state,
        const SearchState(
          status: SearchStatus.ready,
          query: 'reply all',
          results: [podcast],
        ),
      );
    });

    test('clearing the term cancels a pending search', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      bloc.add(const SearchTermChanged('reply'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      bloc.add(const SearchTermChanged('   '));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state, const SearchState());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      verifyZeroInteractions(repository);
      expect(bloc.state, const SearchState());
    });

    for (final fails in [false, true]) {
      for (final duringDebounce in [true, false]) {
        final timing = duringDebounce
            ? 'during the next debounce'
            : 'after newer results';
        test(
          'ignores an old ${fails ? 'error' : 'result'} $timing',
          () async {
            final oldSearch = Completer<List<Podcast>>();
            when(
              () => repository.search('old'),
            ).thenAnswer((_) => oldSearch.future);
            when(
              () => repository.search('new'),
            ).thenAnswer((_) async => [podcast]);
            final bloc = buildBloc();
            addTearDown(bloc.close);
            final states = <SearchState>[];
            final subscription = bloc.stream.listen(states.add);
            addTearDown(subscription.cancel);

            bloc.add(const SearchTermChanged('old'));
            await Future<void>.delayed(Duration.zero);
            await Future<void>.delayed(const Duration(milliseconds: 300));
            verify(() => repository.search('old')).called(1);

            final newResults = bloc.stream
                .firstWhere(
                  (state) =>
                      state.query == 'new' &&
                      state.status == SearchStatus.ready,
                )
                .timeout(const Duration(seconds: 2));
            bloc.add(const SearchTermChanged('new'));
            await Future<void>.delayed(Duration.zero);
            if (!duringDebounce) {
              await newResults;
            }

            final stateCount = states.length;
            if (fails) {
              oldSearch.completeError(const NetworkException('offline'));
            } else {
              oldSearch.complete([]);
            }
            await Future<void>.delayed(Duration.zero);
            expect(states, hasLength(stateCount));

            if (duringDebounce) {
              verifyNever(() => repository.search('new'));
              await newResults;
            }
            verify(() => repository.search('new')).called(1);
            expect(
              bloc.state,
              const SearchState(
                status: SearchStatus.ready,
                query: 'new',
                results: [podcast],
              ),
            );
          },
        );
      }

      test(
        'clearing resets immediately and ignores an in-flight '
        '${fails ? 'error' : 'result'}',
        () async {
          final pending = Completer<List<Podcast>>();
          when(
            () => repository.search('reply'),
          ).thenAnswer((_) => pending.future);
          final bloc = buildBloc();
          addTearDown(bloc.close);

          bloc.add(const SearchTermChanged('reply'));
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(const Duration(milliseconds: 300));
          expect(bloc.state.status, SearchStatus.loading);

          bloc.add(const SearchTermChanged(''));
          await Future<void>.delayed(Duration.zero);
          expect(bloc.state, const SearchState());

          if (fails) {
            pending.completeError(const NetworkException('offline'));
          } else {
            pending.complete([podcast]);
          }
          await Future<void>.delayed(Duration.zero);
          expect(bloc.state, const SearchState());
          verify(() => repository.search('reply')).called(1);
          verifyNoMoreInteractions(repository);
        },
      );
    }

    test('closing during debounce prevents the request', () async {
      final bloc = buildBloc()..add(const SearchTermChanged('reply'));
      await Future<void>.delayed(Duration.zero);

      await bloc.close();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      verifyZeroInteractions(repository);
      expect(bloc.state, const SearchState());
    });
  });
}
