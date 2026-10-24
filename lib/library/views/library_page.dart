import 'package:cabina/common/theme/app_theme.dart';
import 'package:cabina/common/widgets/poster_image.dart';
import 'package:cabina/common/widgets/status_views.dart';
import 'package:cabina/library/cubit/library_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library', style: AppTextStyles.title)),
      body: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          switch (state.status) {
            case LibraryStatus.initial:
            case LibraryStatus.loading:
              return const LoaderView();
            case LibraryStatus.error:
              return ErrorView(
                message: state.errorMessage ?? 'Could not load your library',
                onRetry: () => context.read<LibraryCubit>().load(),
              );
            case LibraryStatus.ready:
              return _LibraryContent(state: state);
          }
        },
      ),
    );
  }
}

class _LibraryContent extends StatelessWidget {
  const _LibraryContent({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Column(
      children: [
        if (state.errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                state.errorMessage!,
                style: TextStyle(color: theme.error),
              ),
            ),
          ),
        Expanded(
          child: state.items.isEmpty
              ? const EmptyView(
                  message: 'Subscribe to a podcast to see it here',
                  icon: Icons.library_music_outlined,
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = state.items[index];
                    return ListTile(
                      key: ValueKey(item.id),
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                        width: 52,
                        height: 52,
                        child: item.artworkUrl == null
                            ? Container(color: theme.surface)
                            : PosterImage(url: item.artworkUrl!, size: 52),
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: 'Unsubscribe from ${item.title}',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () =>
                            context.read<LibraryCubit>().unsubscribe(
                              item.id,
                            ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
