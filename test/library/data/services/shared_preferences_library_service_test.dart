import 'dart:async';
import 'dart:convert';

import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/library/data/services/shared_preferences_library_service.dart';
import 'package:cabina/library/models/subscribed_podcast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockPreferences extends Mock implements SharedPreferences {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'library_podcasts';
  const favouritesKey = 'favourite_podcast_ids';
  const podcast = SubscribedPodcast(id: 1, title: 'Café | news;', author: 'A');
  const second = SubscribedPodcast(
    id: 2,
    title: 'Second',
    author: 'Other',
    artworkUrl: 'https://example.com/art.jpg',
  );

  Future<SharedPreferences> preferences(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('subscriptions cannot change before a successful load', () async {
    final prefs = await preferences({});
    final service = SharedPreferencesLibraryService(prefs: prefs);
    await expectLater(
      service.subscribe(podcast),
      throwsA(isA<LibraryStorageException>()),
    );
    await expectLater(
      service.unsubscribe(podcast.id),
      throwsA(isA<LibraryStorageException>()),
    );
    expect(prefs.getKeys(), isEmpty);
  });

  test('duplicate subscriptions and absent removals do not write', () async {
    final prefs = _MockPreferences();
    when(() => prefs.get(key)).thenReturn(jsonEncode([podcast.toJson()]));
    final service = SharedPreferencesLibraryService(prefs: prefs);
    await service.load();

    await service.subscribe(podcast);
    await service.unsubscribe(second.id);

    verifyNever(() => prefs.setString(any(), any()));
    expect(await service.load(), [podcast]);
  });

  for (final afterFailure in [false, true]) {
    test(
      'overlapping changes preserve every operation ($afterFailure)',
      () async {
        final prefs = _MockPreferences();
        String? cache;
        var fail = afterFailure;
        final refresh = Completer<void>();
        final writes = <Completer<bool>>[];
        final snapshots = <List<SubscribedPodcast>>[];
        when(() => prefs.get(key)).thenAnswer((_) => cache);
        when(prefs.reload).thenAnswer((_) async {
          await refresh.future;
          cache = null;
        });
        when(() => prefs.setString(key, any())).thenAnswer((call) {
          cache = call.positionalArguments[1] as String;
          if (fail) return Future.value(false);
          snapshots.add(
            (jsonDecode(cache!) as List)
                .map(
                  (item) =>
                      SubscribedPodcast.fromJson(item as Map<String, dynamic>),
                )
                .toList(),
          );
          final write = Completer<bool>();
          writes.add(write);
          return write.future;
        });
        final service = SharedPreferencesLibraryService(prefs: prefs);
        await service.load();
        if (afterFailure) {
          await expectLater(
            service.subscribe(podcast),
            throwsA(isA<LibraryStorageException>()),
          );
          fail = false;
        }

        final changes = [
          service.subscribe(podcast),
          service.subscribe(second),
          service.unsubscribe(podcast.id),
        ];
        if (afterFailure) {
          verify(prefs.reload).called(1);
          refresh.complete();
        }
        await Future<void>.delayed(Duration.zero);

        expect(snapshots, [
          [podcast],
          [podcast, second],
          [second],
        ]);
        for (final write in writes) {
          write.complete(true);
        }
        await Future.wait(changes);
        expect(await service.load(), [second]);
      },
    );
  }

  test('an absent library loads empty without writing preferences', () async {
    final prefs = await preferences({favouritesKey: '[7,8]'});
    final result = await SharedPreferencesLibraryService(prefs: prefs).load();
    expect(result, isEmpty);
    expect(prefs.getKeys(), {favouritesKey});
  });

  test(
    'JSON persists ordered subscriptions independently of favourites',
    () async {
      final prefs = await preferences({favouritesKey: '[7,8]'});
      final service = SharedPreferencesLibraryService(prefs: prefs);
      await service.load();
      await service.subscribe(podcast);
      await service.subscribe(second);
      expect(jsonDecode(prefs.getString(key)!), [
        podcast.toJson(),
        second.toJson(),
      ]);
      await prefs.reload();

      final loaded = await SharedPreferencesLibraryService(prefs: prefs).load();
      expect(loaded, [podcast, second]);
      expect(loaded.clear, throwsUnsupportedError);
      expect(prefs.getString(favouritesKey), '[7,8]');
    },
  );

  test('removing every subscription persists an empty list', () async {
    final prefs = await preferences({
      key: jsonEncode([podcast.toJson()]),
    });
    final service = SharedPreferencesLibraryService(prefs: prefs);
    expect(await service.load(), [podcast]);
    await service.unsubscribe(podcast.id);
    await prefs.reload();

    expect(prefs.getString(key), '[]');
    expect(await SharedPreferencesLibraryService(prefs: prefs).load(), isEmpty);
  });

  final invalidValues = <Object>[
    '',
    '{broken',
    '{}',
    '[null]',
    '[{"id":1.5,"title":"T","author":"A"}]',
    '[{"id":1,"title":"T"}]',
    '[{"id":1,"title":"T","author":"A","artworkUrl":7}]',
    42,
  ];
  for (var index = 0; index < invalidValues.length; index++) {
    test(
      'invalid JSON case $index reports an error without overwriting',
      () async {
        final invalid = invalidValues[index];
        final prefs = await preferences({key: invalid});
        final service = SharedPreferencesLibraryService(prefs: prefs);

        await expectLater(
          service.load(),
          throwsA(isA<LibraryStorageException>()),
        );
        await expectLater(
          service.unsubscribe(podcast.id),
          throwsA(isA<LibraryStorageException>()),
        );
        await expectLater(
          service.subscribe(podcast),
          throwsA(isA<LibraryStorageException>()),
        );
        expect(prefs.get(key), invalid);
      },
    );
  }

  for (final throwsException in [false, true]) {
    test(
      'a failed save does not become a cached success ($throwsException)',
      () async {
        final prefs = _MockPreferences();
        final stored = <String, Object>{};
        final cache = <String, Object>{};
        var fail = true;
        when(() => prefs.get(any())).thenAnswer(
          (call) => cache[call.positionalArguments.first],
        );
        when(prefs.reload).thenAnswer((_) async {
          cache
            ..clear()
            ..addAll(stored);
        });
        when(() => prefs.setString(any(), any())).thenAnswer((call) async {
          final name = call.positionalArguments[0] as String;
          final value = call.positionalArguments[1] as String;
          cache[name] = value;
          if (fail) {
            if (throwsException) throw PlatformException(code: 'write_failed');
            return false;
          }
          stored[name] = value;
          return true;
        });
        final service = SharedPreferencesLibraryService(prefs: prefs);
        await service.load();

        await expectLater(
          service.subscribe(podcast),
          throwsA(isA<LibraryStorageException>()),
        );
        expect(stored, isEmpty);
        expect(cache.containsKey(key), isTrue);
        expect(await service.load(), isEmpty);
        verify(prefs.reload).called(1);

        fail = false;
        await service.subscribe(podcast);
        expect(jsonDecode(stored[key]! as String), [podcast.toJson()]);
        expect(await service.load(), [podcast]);
        verify(() => prefs.setString(key, any())).called(2);
      },
    );
  }

  test('save failures refresh the cache before a direct retry', () async {
    final prefs = _MockPreferences();
    when(() => prefs.get(any())).thenReturn(null);
    when(prefs.reload).thenAnswer((_) async {});
    when(() => prefs.setString(any(), any())).thenAnswer((_) async => false);
    final service = SharedPreferencesLibraryService(prefs: prefs);
    await service.load();

    await expectLater(
      service.subscribe(podcast),
      throwsA(isA<LibraryStorageException>()),
    );
    when(() => prefs.setString(any(), any())).thenAnswer((_) async => true);
    await service.subscribe(podcast);

    verifyInOrder([
      () => prefs.setString(key, any()),
      prefs.reload,
      () => prefs.setString(key, any()),
    ]);
  });
}
