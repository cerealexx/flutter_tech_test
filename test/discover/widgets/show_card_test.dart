import 'package:cabina/common/theme/app_theme.dart';
import 'package:cabina/discover/cubit/discover_cubit.dart';
import 'package:cabina/discover/data/discover_repository.dart';
import 'package:cabina/discover/data/favourites_repository.dart';
import 'package:cabina/discover/models/podcast.dart';
import 'package:cabina/discover/widgets/show_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDiscoverRepository extends Mock implements DiscoverRepository {}

void main() {
  const favouritesKey = 'favourite_podcast_ids';
  const podcast = Podcast(
    id: 7,
    title: 'Test podcast',
    author: 'Author',
    feedUrl: 'https://example.com/feed.xml',
    artworkUrl: 'https://example.com/artwork.jpg',
  );

  for (final initiallyFavourite in [false, true]) {
    testWidgets(
      'heart updates and persists with '
      '${initiallyFavourite ? 'saved favourites' : 'no saved favourites'}',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          if (initiallyFavourite) favouritesKey: '[7,8]',
        });
        final prefs = await SharedPreferences.getInstance();
        DiscoverCubit buildCubit() {
          final cubit = DiscoverCubit(
            discoverRepository: _MockDiscoverRepository(),
            favouritesRepository: FavouritesRepository(prefs: prefs),
          );
          addTearDown(cubit.close);
          return cubit;
        }

        final cubit = buildCubit();
        final initialState = cubit.state;
        var openedShow = false;
        await tester.pumpWidget(
          BlocProvider.value(
            value: cubit,
            child: MaterialApp(
              theme: AppTheme(isDark: false).toThemeData(),
              home: Scaffold(
                body: SizedBox(
                  width: 200,
                  height: 280,
                  child: ShowCard(
                    podcast: podcast,
                    onTap: () => openedShow = true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final initialIcon = initiallyFavourite
            ? Icons.favorite
            : Icons.favorite_border;
        final toggledIcon = initiallyFavourite
            ? Icons.favorite_border
            : Icons.favorite;
        await tester.tap(find.byIcon(initialIcon));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byIcon(toggledIcon), findsOneWidget);
        expect(openedShow, isFalse);
        expect(
          initialState.favouriteIds,
          initiallyFavourite ? [7, 8] : <int>[],
        );
        expect(
          prefs.getString(favouritesKey),
          initiallyFavourite ? '[8]' : '[7]',
        );
        expect(
          buildCubit().state.favouriteIds,
          initiallyFavourite ? [8] : [7],
        );

        await tester.tap(find.byIcon(toggledIcon));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byIcon(initialIcon), findsOneWidget);
        expect(
          prefs.getString(favouritesKey),
          initiallyFavourite ? '[8,7]' : '[]',
        );
        expect(
          buildCubit().state.favouriteIds,
          initiallyFavourite ? [8, 7] : <int>[],
        );
      },
    );
  }
}
