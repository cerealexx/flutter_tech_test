import 'package:cabina/discover/views/discover_page.dart';
import 'package:cabina/library/views/library_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum HomeTab { discover, library }

class HomePage extends StatelessWidget {
  const HomePage({this.tab = HomeTab.discover, super.key});

  final HomeTab tab;

  static const routeName = 'home';
  static const routePath = '/';

  static GoRoute route() => GoRoute(
    path: routePath,
    name: routeName,
    builder: (context, state) => HomePage(
      tab: switch (state.uri.queryParameters['tab']) {
        'discover' => HomeTab.discover,
        'library' => HomeTab.library,
        _ => HomeTab.discover,
      },
    ),
  );

  static const List<Widget> _tabs = [DiscoverPage(), LibraryPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: tab.index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.index,
        onDestinationSelected: (index) => context.goNamed(
          routeName,
          queryParameters: {'tab': HomeTab.values[index].name},
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Library',
          ),
        ],
      ),
    );
  }
}
