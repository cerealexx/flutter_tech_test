import 'dart:async';
import 'dart:convert';

import 'package:cabina/app/widgets/app_dependency_injection.dart';
import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/common/network/api_client.dart';
import 'package:cabina/common/router/router.dart';
import 'package:cabina/common/theme/app_theme.dart';
import 'package:cabina/discover/models/podcast.dart';
import 'package:cabina/library/cubit/library_cubit.dart';
import 'package:cabina/library/data/library_repository.dart';
import 'package:cabina/library/data/services/shared_preferences_library_service.dart';
import 'package:cabina/library/models/subscribed_podcast.dart';
import 'package:cabina/library/views/library_page.dart';
import 'package:cabina/show_detail/views/show_detail_page.dart';
import 'package:cabina/show_detail/widgets/subscribe_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockLibraryRepository extends Mock implements LibraryRepository {}

class _MockApiClient extends Mock implements ApiClient {}

const _podcast = SubscribedPodcast(
  id: 1,
  title: 'Test podcast',
  author: 'Author',
);
const _button = SubscribeButton(id: 1, title: 'Test podcast', author: 'Author');

Future<void> _pumpLibrary(
  WidgetTester tester,
  LibraryCubit cubit, {
  bool isDark = false,
}) {
  return tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: MaterialApp(
        theme: AppTheme(isDark: isDark).toThemeData(),
        home: const Scaffold(
          body: Column(
            children: [
              _button,
              Expanded(child: LibraryPage()),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  late _MockLibraryRepository repository;

  setUpAll(() => registerFallbackValue(_podcast));

  setUp(() {
    repository = _MockLibraryRepository();
    when(() => repository.load()).thenAnswer(
      (_) async => [],
    );
    when(() => repository.subscribe(any())).thenAnswer((_) async {});
    when(() => repository.unsubscribe(any())).thenAnswer((_) async {});
  });

  LibraryCubit buildCubit() {
    final cubit = LibraryCubit(repository: repository);
    addTearDown(cubit.close);
    return cubit;
  }

  for (final isDark in [false, true]) {
    testWidgets(
      'button toggles immediately and throttles repeats in '
      '${isDark ? 'dark' : 'light'} mode',
      (tester) async {
        final pending = Completer<void>();
        when(
          () => repository.subscribe(any()),
        ).thenAnswer((_) => pending.future);
        when(
          () => repository.unsubscribe(any()),
        ).thenAnswer((_) => pending.future);
        final cubit = buildCubit();
        await _pumpLibrary(tester, cubit, isDark: isDark);
        await tester.pumpAndSettle();
        final button = find.byType(FilledButton);
        final material = find.descendant(
          of: button,
          matching: find.byType(Material),
        );

        final background = tester.widget<Material>(material).color;

        for (final label in ['Subscribe', 'Unsubscribe']) {
          await tester.tap(find.text(label));
          await tester.pump();

          final subscribed = label == 'Subscribe';
          expect(
            find.text(subscribed ? 'Unsubscribe' : 'Subscribe'),
            findsOneWidget,
          );
          expect(find.byType(ListTile), findsNWidgets(subscribed ? 1 : 0));
          expect(tester.widget<Material>(material).color, background);
          expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
          expect(find.byType(CircularProgressIndicator), findsNothing);

          await tester.tap(button);
          await tester.pump();
          expect(cubit.state.isSubscribed(_podcast.id), subscribed);

          await tester.pump(const Duration(milliseconds: 299));
          await tester.tap(button);
          await tester.pump();
          expect(cubit.state.isSubscribed(_podcast.id), subscribed);

          // Ignored taps do not extend the original 300 ms interval.
          await tester.pump(const Duration(milliseconds: 1));
        }
        pending.complete();
        await tester.pumpAndSettle();
        verifyInOrder([
          () => repository.subscribe(_podcast),
          () => repository.unsubscribe(_podcast.id),
        ]);
        expect(find.text('Subscribe'), findsOneWidget);
        expect(find.byType(ListTile), findsNothing);
      },
    );
  }

  testWidgets('disposing the button cancels its throttle timer', (
    tester,
  ) async {
    final cubit = buildCubit();
    await _pumpLibrary(tester, cubit);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Subscribe'));
    expect(cubit.state.isSubscribed(_podcast.id), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());

    verify(() => repository.subscribe(_podcast)).called(1);
    verifyNever(() => repository.unsubscribe(any()));
  });

  testWidgets('initial loading never offers an incorrect subscription action', (
    tester,
  ) async {
    final pending = Completer<List<SubscribedPodcast>>();
    when(() => repository.load()).thenAnswer((_) => pending.future);
    final cubit = buildCubit();
    await _pumpLibrary(tester, cubit);
    expect(find.text('Subscribe'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    expect(find.text('Loading library…'), findsOneWidget);
    pending.complete([_podcast]);
    await tester.pumpAndSettle();
    expect(find.text('Unsubscribe'), findsOneWidget);
    expect(find.text('Test podcast'), findsOneWidget);
  });

  testWidgets('a load error links to Library and is retried only there', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'library_podcasts': 'invalid JSON',
    });
    final prefs = await SharedPreferences.getInstance();
    final apiClient = _MockApiClient();
    final searchUri = Uri.https('itunes.apple.com', '/search', {
      'media': 'podcast',
      'entity': 'podcast',
      'term': 'top shows',
      'limit': '50',
    });
    const podcast = Podcast(
      id: 1,
      title: 'Test podcast',
      author: 'Author',
      feedUrl: 'https://example.com/feed.xml',
    );
    final feedUri = Uri.parse(podcast.feedUrl);
    when(() => apiClient.getString(searchUri)).thenAnswer(
      (_) async => '{"results": []}',
    );
    when(() => apiClient.getString(feedUri)).thenAnswer(
      (_) async => '<rss><channel /></rss>',
    );
    final router = RouterBuilder.build();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      AppDependencyInjection(
        prefs: prefs,
        apiClient: apiClient,
        child: MaterialApp.router(
          theme: AppTheme(isDark: false).toThemeData(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mountedLibrary = tester.element(
      find.byType(LibraryPage, skipOffstage: false),
    );
    final cubit = mountedLibrary.read<LibraryCubit>();

    unawaited(router.pushNamed<void>(ShowDetailPage.routeName, extra: podcast));
    await tester.pumpAndSettle();
    expect(find.text('Unexpected library error.'), findsOneWidget);
    expect(find.text('Open library'), findsOneWidget);
    expect(find.text('Subscribe'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);

    await prefs.setString(
      'library_podcasts',
      jsonEncode([_podcast.toJson()]),
    );
    await tester.tap(find.text('Open library'));
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(LibraryPage)), same(mountedLibrary));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(cubit.state.status, LibraryStatus.error);
    expect(
      find.text('Could not load your library. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(SubscribeButton), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(cubit.state.status, LibraryStatus.ready);
    expect(find.text(_podcast.title), findsOneWidget);

    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(router.routeInformationProvider.value.uri.queryParameters, {
      'tab': 'discover',
    });
    unawaited(router.pushNamed<void>(ShowDetailPage.routeName, extra: podcast));
    await tester.pumpAndSettle();
    expect(find.text('Unsubscribe'), findsOneWidget);
    expect(find.text('Open library'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('save errors restore both views and allow retrying', (
    tester,
  ) async {
    final pending = Completer<void>();
    when(() => repository.subscribe(any())).thenAnswer((_) => pending.future);
    final cubit = buildCubit();
    await _pumpLibrary(tester, cubit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscribe'));
    await tester.pump();

    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Unsubscribe'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    pending.completeError(const LibraryStorageException('Could not save'));
    await tester.pumpAndSettle();
    expect(find.text('Subscribe'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Could not save'), findsNWidgets(2));

    when(() => repository.subscribe(any())).thenAnswer((_) async {});
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();
    expect(find.text('Unsubscribe'), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Could not save'), findsNothing);

    final removal = Completer<void>();
    when(() => repository.unsubscribe(any())).thenAnswer((_) => removal.future);
    await tester.tap(find.byTooltip('Unsubscribe from Test podcast'));
    await tester.pump();
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Subscribe'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    removal.completeError(const LibraryStorageException('Could not save'));
    await tester.pumpAndSettle();
    expect(find.text('Unsubscribe'), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Could not save'), findsNWidgets(2));

    when(() => repository.unsubscribe(any())).thenAnswer((_) async {});
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Unsubscribe'));
    await tester.pumpAndSettle();
    expect(find.text('Subscribe'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Could not save'), findsNothing);
  });

  testWidgets(
    'app scope keeps an IndexedStack library and detail route in sync',
    (tester) async {
      SharedPreferences.setMockInitialValues({'favourite_podcast_ids': '[9]'});
      final prefs = await SharedPreferences.getInstance();
      var tab = 0;
      late LibraryCubit appCubit;
      LibraryCubit? detailCubit;

      await tester.pumpWidget(
        AppDependencyInjection(
          prefs: prefs,
          apiClient: _MockApiClient(),
          child: MaterialApp(
            theme: AppTheme(isDark: false).toThemeData(),
            home: StatefulBuilder(
              builder: (context, setState) {
                appCubit = context.read<LibraryCubit>();
                return Scaffold(
                  body: IndexedStack(
                    index: tab,
                    children: [
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (context) {
                                  detailCubit = context.read<LibraryCubit>();
                                  return Scaffold(
                                    appBar: AppBar(
                                      title: const Text('Detail'),
                                    ),
                                    body: const Center(child: _button),
                                  );
                                },
                              ),
                            );
                          },
                          child: const Text('Open detail'),
                        ),
                      ),
                      const LibraryPage(),
                    ],
                  ),
                  bottomNavigationBar: NavigationBar(
                    selectedIndex: tab,
                    onDestinationSelected: (value) =>
                        setState(() => tab = value),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.explore),
                        label: 'Discover',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.library_music),
                        label: 'My library',
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mountedLibrary = tester.element(
        find.byType(LibraryPage, skipOffstage: false),
      );

      await tester.tap(find.text('Open detail'));
      await tester.pumpAndSettle();
      expect(detailCubit, same(appCubit));
      await tester.tap(find.text('Subscribe'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('My library'));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(LibraryPage)), same(mountedLibrary));
      expect(find.text('Test podcast'), findsOneWidget);

      await tester.tap(find.byTooltip('Unsubscribe from Test podcast'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discover'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open detail'));
      await tester.pumpAndSettle();
      expect(find.text('Subscribe'), findsOneWidget);
      expect(prefs.getString('favourite_podcast_ids'), '[9]');

      await prefs.reload();
      expect(
        await SharedPreferencesLibraryService(prefs: prefs).load(),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(appCubit.isClosed, isTrue);
    },
  );
}
