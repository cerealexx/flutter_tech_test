import 'package:cabina/library/models/subscribed_podcast.dart';

abstract class ILibraryService {
  Future<List<SubscribedPodcast>> load();
  Future<void> subscribe(SubscribedPodcast podcast);
  Future<void> unsubscribe(int podcastId);
}
