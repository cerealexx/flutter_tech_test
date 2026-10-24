import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/library/cubit/library_cubit.dart';
import 'package:cabina/library/data/library_repository.dart';
import 'package:cabina/library/models/subscribed_podcast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockLibraryRepository extends Mock implements LibraryRepository {}

void main() {
  const first = SubscribedPodcast(id: 1, title: 'First', author: 'Author');
  const second = SubscribedPodcast(id: 2, title: 'Second', author: 'Author');
  const failure = LibraryStorageException('Storage unavailable');
  late _MockLibraryRepository repository;

  setUpAll(() => registerFallbackValue(first));

  setUp(() {
    repository = _MockLibraryRepository();
    when(() => repository.load()).thenAnswer(
      (_) async => const [],
    );
    when(() => repository.subscribe(any())).thenAnswer((_) async {});
    when(() => repository.unsubscribe(any())).thenAnswer((_) async {});
  });

  LibraryCubit buildCubit() => LibraryCubit(repository: repository);

  Future<void> waitForStatus(LibraryCubit cubit, LibraryStatus status) async {
    if (cubit.state.status != status) {
      await cubit.stream.firstWhere((state) => state.status == status);
    }
  }

  blocTest<LibraryCubit, LibraryState>(
    'loads subscriptions automatically only once',
    build: () {
      when(() => repository.load()).thenAnswer(
        (_) async => const [first],
      );
      return buildCubit();
    },
    act: (cubit) async {
      await waitForStatus(cubit, LibraryStatus.ready);
      await cubit.load();
    },
    expect: () => [
      LibraryState(
        status: LibraryStatus.ready,
        items: const [first],
      ),
    ],
    verify: (_) => verify(() => repository.load()).called(1),
  );

  blocTest<LibraryCubit, LibraryState>(
    'retries a failed automatic load and clears its error',
    build: () {
      when(() => repository.load()).thenAnswer((_) async => throw failure);
      return buildCubit();
    },
    act: (cubit) async {
      await waitForStatus(cubit, LibraryStatus.error);
      when(() => repository.load()).thenAnswer(
        (_) async => const [first],
      );
      await cubit.load();
    },
    expect: () => [
      LibraryState(status: LibraryStatus.error, errorMessage: failure.message),
      LibraryState(status: LibraryStatus.loading),
      LibraryState(status: LibraryStatus.ready, items: const [first]),
    ],
  );

  test('does not load twice before a load completes', () async {
    final pending = Completer<List<SubscribedPodcast>>();
    when(() => repository.load()).thenAnswer((_) => pending.future);
    final cubit = buildCubit();
    addTearDown(cubit.close);
    expect(cubit.state.status, LibraryStatus.loading);
    await cubit.load();
    verify(() => repository.load()).called(1);
    pending.complete(const [second]);
    await waitForStatus(cubit, LibraryStatus.ready);
    expect(cubit.state.items, [second]);
  });

  test('updates immediately without waiting for previous saves', () async {
    final writes = List.generate(3, (_) => Completer<void>());
    when(() => repository.subscribe(first)).thenAnswer((_) => writes[0].future);
    when(
      () => repository.subscribe(second),
    ).thenAnswer((_) => writes[1].future);
    when(
      () => repository.unsubscribe(first.id),
    ).thenAnswer((_) => writes[2].future);
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await waitForStatus(cubit, LibraryStatus.ready);
    final firstChange = cubit.subscribe(first);
    expect(cubit.state.items, [first]);
    final secondChange = cubit.subscribe(second);
    expect(cubit.state.items, [first, second]);
    final thirdChange = cubit.unsubscribe(first.id);
    expect(cubit.state.items, [second]);

    verifyInOrder([
      () => repository.subscribe(first),
      () => repository.subscribe(second),
      () => repository.unsubscribe(first.id),
    ]);
    writes[2].complete();
    await thirdChange;
    expect(cubit.state.items, [second]);
    writes[0].complete();
    await firstChange;
    expect(cubit.state.items, [second]);
    writes[1].complete();
    await secondChange;
    expect(cubit.state.items, [second]);
  });

  blocTest<LibraryCubit, LibraryState>(
    'a failed removal restores the previous state and retry clears errors',
    build: () {
      when(
        () => repository.load(),
      ).thenAnswer((_) async => const [first, second]);
      return buildCubit();
    },
    act: (cubit) async {
      await waitForStatus(cubit, LibraryStatus.ready);
      when(() => repository.subscribe(any())).thenThrow(failure);
      when(() => repository.unsubscribe(any())).thenThrow(failure);
      await cubit.unsubscribe(first.id);
      when(() => repository.subscribe(any())).thenAnswer((_) async {});
      when(() => repository.unsubscribe(any())).thenAnswer((_) async {});
      await cubit.unsubscribe(first.id);
    },
    expect: () => [
      LibraryState(status: LibraryStatus.ready, items: const [first, second]),
      LibraryState(status: LibraryStatus.ready, items: const [second]),
      LibraryState(
        status: LibraryStatus.ready,
        items: const [first, second],
        errorMessage: failure.message,
        failedPodcastId: 1,
      ),
      LibraryState(status: LibraryStatus.ready, items: const [second]),
    ],
  );

  test(
    'a failed subscription restores the previous state and reports the error',
    () async {
      when(() => repository.subscribe(any())).thenThrow(failure);
      when(() => repository.unsubscribe(any())).thenThrow(failure);
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await waitForStatus(cubit, LibraryStatus.ready);
      await cubit.subscribe(first);
      expect(cubit.state.isSubscribed(first.id), isFalse);
      expect(cubit.state.errorMessage, failure.message);
      expect(cubit.state.failedPodcastId, first.id);
    },
  );

  test(
    'a failed save restores the snapshot captured before its change',
    () async {
      when(() => repository.load()).thenAnswer((_) async => [second]);
      final firstWrite = Completer<void>();
      when(
        () => repository.subscribe(first),
      ).thenAnswer((_) => firstWrite.future);
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await waitForStatus(cubit, LibraryStatus.ready);

      final subscribing = cubit.subscribe(first);
      expect(cubit.state.items, [second, first]);
      await cubit.unsubscribe(second.id);
      expect(cubit.state.items, [first]);
      firstWrite.completeError(failure);
      await subscribing;

      expect(cubit.state.items, [second]);
      expect(cubit.state.errorMessage, failure.message);
      expect(cubit.state.failedPodcastId, first.id);
    },
  );
}
