import 'dart:async';

import 'package:cabina/common/theme/app_theme.dart';
import 'package:cabina/common/widgets/poster_image.dart';
import 'package:cabina/common/widgets/status_views.dart';
import 'package:cabina/episode_insights/cubit/episode_insights_cubit.dart';
import 'package:cabina/episode_insights/data/episode_insights_repository.dart';
import 'package:cabina/episode_insights/widgets/episode_insights_drawer.dart';
import 'package:cabina/player/bloc/audio_player_bloc.dart';
import 'package:cabina/player/data/audio_player_repository.dart';
import 'package:cabina/player/data/services/just_audio_player_service.dart';
import 'package:cabina/player/models/player_args.dart';
import 'package:cabina/player/models/player_status.dart';
import 'package:cabina/player/widgets/player_controls.dart';
import 'package:cabina/player/widgets/seek_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({required this.args, super.key});

  final PlayerArgs args;

  static const routeName = 'player';
  static const routePath = '/player';

  static GoRoute route() => GoRoute(
    path: routePath,
    name: routeName,
    builder: (context, state) {
      final args = state.extra! as PlayerArgs;
      return MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => AudioPlayerBloc(
              repository: AudioPlayerRepository(
                service: JustAudioPlayerService(),
              ),
            ),
          ),
          BlocProvider(
            create: (context) => EpisodeInsightsCubit(
              repository: context.read<EpisodeInsightsRepository>(),
              episode: args.episode,
            ),
          ),
        ],
        child: PlayerPage(args: args),
      );
    },
  );

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final EpisodeInsightsCubit _insights;
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _insights = context.read<EpisodeInsightsCubit>();
    unawaited(_insights.generate());
    final repository = context.read<EpisodeInsightsRepository>();
    unawaited(_openPlayer(repository));
  }

  Future<void> _openPlayer(EpisodeInsightsRepository repository) async {
    final player = context.read<AudioPlayerBloc>();
    final source = await repository.cachedAudioUri(widget.args.episode);
    if (!mounted) return;
    player.add(PlayerOpened(widget.args, sourceUri: source));
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        title: const Text('Now Playing'),
        actions: [
          BlocBuilder<EpisodeInsightsCubit, EpisodeInsightsState>(
            builder: (context, state) => IconButton(
              tooltip: 'Episode summary',
              icon: Badge(
                isLabelVisible: state.isBusy,
                child: const Icon(Icons.summarize_outlined),
              ),
              onPressed: () => _scaffold.currentState?.openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: EpisodeInsightsDrawer(
        title: widget.args.episode.title,
        cubit: _insights,
        onTopic: (topic, audioUri) {
          _scaffold.currentState?.closeEndDrawer();
          context.read<AudioPlayerBloc>().add(
            PlayerTopicSelected(position: topic.start, audioUri: audioUri),
          );
        },
      ),
      body: BlocBuilder<AudioPlayerBloc, AudioPlayerState>(
        builder: (context, state) {
          if (state.status == PlayerStatus.error) {
            return ErrorView(message: state.errorMessage ?? 'Playback failed');
          }
          final args = state.args ?? widget.args;
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              children: [
                const Spacer(),
                AspectRatio(
                  aspectRatio: 1,
                  child: args.artworkUrl == null
                      ? Container(
                          decoration: BoxDecoration(
                            color: theme.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.podcasts,
                            size: 64,
                            color: theme.foregroundSoft,
                          ),
                        )
                      : PosterImage(url: args.artworkUrl!, borderRadius: 20),
                ),
                const SizedBox(height: 28),
                Text(
                  args.episode.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headline.copyWith(
                    color: theme.foreground,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  args.podcastTitle,
                  style: AppTextStyles.caption.copyWith(
                    color: theme.foregroundSoft,
                  ),
                ),
                const Spacer(),
                SeekBar(position: state.position),
                const SizedBox(height: 12),
                PlayerControls(
                  status: state.status,
                  speed: state.speed,
                  position: state.position,
                ),
                const Spacer(),
              ],
            ),
          );
        },
      ),
    );
  }
}
