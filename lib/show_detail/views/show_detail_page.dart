import 'package:cabina/common/theme/app_theme.dart';
import 'package:cabina/common/widgets/poster_image.dart';
import 'package:cabina/common/widgets/status_views.dart';
import 'package:cabina/discover/models/podcast.dart';
import 'package:cabina/player/models/player_args.dart';
import 'package:cabina/player/views/player_page.dart';
import 'package:cabina/show_detail/bloc/show_detail_bloc.dart';
import 'package:cabina/show_detail/data/show_detail_repository.dart';
import 'package:cabina/show_detail/models/podcast_detail.dart';
import 'package:cabina/show_detail/widgets/episode_tile.dart';
import 'package:cabina/show_detail/widgets/subscribe_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class ShowDetailPage extends StatefulWidget {
  const ShowDetailPage({required this.podcast, super.key});

  final Podcast podcast;

  static const routeName = 'showDetail';
  static const routePath = '/show';

  static GoRoute route() => GoRoute(
    path: routePath,
    name: routeName,
    builder: (context, state) {
      final podcast = state.extra! as Podcast;
      return BlocProvider(
        create: (ctx) => ShowDetailBloc(
          repository: ctx.read<ShowDetailRepository>(),
        ),
        child: ShowDetailPage(podcast: podcast),
      );
    },
  );

  @override
  State<ShowDetailPage> createState() => _ShowDetailPageState();
}

class _ShowDetailPageState extends State<ShowDetailPage> {
  @override
  void initState() {
    super.initState();
    context.read<ShowDetailBloc>().add(ShowDetailRequested(widget.podcast));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.podcast.title, maxLines: 1)),
      body: BlocBuilder<ShowDetailBloc, ShowDetailState>(
        builder: (context, state) {
          switch (state.status) {
            case ShowDetailStatus.initial:
            case ShowDetailStatus.loading:
              return const LoaderView();
            case ShowDetailStatus.error:
              return ErrorView(
                message: state.errorMessage ?? 'Could not load this podcast',
                onRetry: () => context
                    .read<ShowDetailBloc>()
                    .add(ShowDetailRequested(widget.podcast)),
              );
            case ShowDetailStatus.ready:
              return _DetailContent(
                detail: state.detail!,
                podcast: widget.podcast,
              );
          }
        },
      ),
    );
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({required this.detail, required this.podcast});

  final PodcastDetail detail;
  final Podcast podcast;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: detail.episodes.length + 1,
      separatorBuilder: (context, index) =>
          index == 0 ? const SizedBox.shrink() : const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: detail.artworkUrl == null
                        ? Container(color: theme.surface)
                        : PosterImage(url: detail.artworkUrl!, size: 96),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(detail.title, style: AppTextStyles.headline),
                        const SizedBox(height: 4),
                        Text(
                          detail.author,
                          style: AppTextStyles.caption.copyWith(
                            color: theme.foregroundSoft,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SubscribeButton(
                          id: podcast.id,
                          title: detail.title,
                          author: detail.author,
                          artworkUrl: detail.artworkUrl,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (detail.descriptionHtml.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  detail.descriptionHtml,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    color: theme.foregroundSoft,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '${detail.episodes.length} episodes',
                style: AppTextStyles.label.copyWith(
                  color: theme.foregroundSoft,
                ),
              ),
            ],
          );
        }

        final episode = detail.episodes[index - 1];
        return EpisodeTile(
          episode: episode,
          onTap: () => context.pushNamed(
            PlayerPage.routeName,
            extra: PlayerArgs(
              episode: episode,
              podcastTitle: detail.title,
              artworkUrl: episode.imageUrl ?? detail.artworkUrl,
            ),
          ),
        );
      },
    );
  }
}
