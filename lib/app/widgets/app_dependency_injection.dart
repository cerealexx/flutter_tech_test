import 'package:cabina/common/env/env.dart';
import 'package:cabina/common/network/api_client.dart';
import 'package:cabina/common/services/itunes_search_service.dart';
import 'package:cabina/discover/cubit/discover_cubit.dart';
import 'package:cabina/discover/data/discover_repository.dart';
import 'package:cabina/discover/data/favourites_repository.dart';
import 'package:cabina/episode_insights/data/episode_insights_repository.dart';
import 'package:cabina/episode_insights/data/services/audio_chunk_service.dart';
import 'package:cabina/episode_insights/data/services/audio_download_service.dart';
import 'package:cabina/episode_insights/data/services/episode_insights_service.dart';
import 'package:cabina/episode_insights/data/services/i_episode_insights_service.dart';
import 'package:cabina/episode_insights/data/services/insights_cache_service.dart';
import 'package:cabina/episode_insights/data/services/openai_insights_service.dart';
import 'package:cabina/library/cubit/library_cubit.dart';
import 'package:cabina/library/data/library_repository.dart';
import 'package:cabina/library/data/services/i_library_service.dart';
import 'package:cabina/library/data/services/shared_preferences_library_service.dart';
import 'package:cabina/search/data/search_repository.dart';
import 'package:cabina/show_detail/data/services/rss_feed_service.dart';
import 'package:cabina/show_detail/data/show_detail_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wires the object graph (services → repositories → app-scoped blocs) using
/// `RepositoryProvider`/`BlocProvider`. Route-scoped blocs (search, show detail, player) are
/// created in the router.
class AppDependencyInjection extends StatelessWidget {
  const AppDependencyInjection({
    required this.prefs,
    required this.apiClient,
    required this.child,
    super.key,
  });

  final SharedPreferences prefs;
  final ApiClient apiClient;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<IEpisodeInsightsService>(
          create: (_) {
            final openAi = OpenAiInsightsService(
              apiKey: Env.llmApiKey,
              model: Env.summaryModel,
            );
            return EpisodeInsightsService(
              configured: Env.llmApiKey.trim().isNotEmpty,
              cache: InsightsCacheService(),
              downloader: AudioDownloadService(),
              chunks: const NativeAudioChunkService(),
              transcriber: openAi,
              summarizer: openAi,
            );
          },
        ),
        RepositoryProvider(
          create: (ctx) => EpisodeInsightsRepository(
            service: ctx.read<IEpisodeInsightsService>(),
          ),
        ),
        RepositoryProvider(
          create: (ctx) => ItunesSearchService(apiClient: apiClient),
        ),
        RepositoryProvider(
          create: (ctx) => DiscoverRepository(
            searchService: ctx.read<ItunesSearchService>(),
          ),
        ),
        RepositoryProvider(
          create: (ctx) =>
              SearchRepository(searchService: ctx.read<ItunesSearchService>()),
        ),
        RepositoryProvider(
          create: (ctx) => RssFeedService(apiClient: apiClient),
        ),
        RepositoryProvider(
          create: (ctx) =>
              ShowDetailRepository(feedService: ctx.read<RssFeedService>()),
        ),
        RepositoryProvider(
          create: (_) => FavouritesRepository(prefs: prefs),
        ),
        RepositoryProvider<ILibraryService>(
          create: (_) => SharedPreferencesLibraryService(prefs: prefs),
        ),
        RepositoryProvider(
          create: (ctx) =>
              LibraryRepository(service: ctx.read<ILibraryService>()),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (ctx) => LibraryCubit(
              repository: ctx.read<LibraryRepository>(),
            ),
          ),
          BlocProvider(
            create: (ctx) => DiscoverCubit(
              discoverRepository: ctx.read<DiscoverRepository>(),
              favouritesRepository: ctx.read<FavouritesRepository>(),
            ),
          ),
        ],
        child: child,
      ),
    );
  }
}
