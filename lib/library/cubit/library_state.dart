part of 'library_cubit.dart';

enum LibraryStatus { initial, loading, ready, error }

class LibraryState extends Equatable {
  LibraryState({
    this.status = LibraryStatus.initial,
    List<SubscribedPodcast> items = const [],
    this.errorMessage,
    this.failedPodcastId,
  }) : items = List.unmodifiable(items);

  final LibraryStatus status;
  final List<SubscribedPodcast> items;
  final String? errorMessage;
  final int? failedPodcastId;

  bool isSubscribed(int id) => items.any((item) => item.id == id);

  LibraryState copyWith({
    List<SubscribedPodcast>? items,
    String? errorMessage,
    int? failedPodcastId,
  }) {
    return LibraryState(
      status: status,
      items: items ?? this.items,
      errorMessage: errorMessage,
      failedPodcastId: failedPodcastId,
    );
  }

  @override
  List<Object?> get props => [
    status,
    items,
    errorMessage,
    failedPodcastId,
  ];
}
