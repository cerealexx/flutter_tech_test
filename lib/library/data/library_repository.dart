import 'package:cabina/library/data/services/i_library_service.dart';
import 'package:cabina/library/models/subscribed_podcast.dart';

class LibraryRepository {
  LibraryRepository({required ILibraryService service}) : _service = service;

  final ILibraryService _service;

  Future<List<SubscribedPodcast>> load() => _service.load();
  Future<void> subscribe(SubscribedPodcast podcast) =>
      _service.subscribe(podcast);
  Future<void> unsubscribe(int podcastId) => _service.unsubscribe(podcastId);
}
