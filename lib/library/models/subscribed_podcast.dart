import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'subscribed_podcast.g.dart';

@JsonSerializable()
class SubscribedPodcast extends Equatable {
  const SubscribedPodcast({
    required this.id,
    required this.title,
    required this.author,
    this.artworkUrl,
  });

  factory SubscribedPodcast.fromJson(Map<String, dynamic> json) =>
      _$SubscribedPodcastFromJson(json);

  final int id;
  final String title;
  final String author;
  final String? artworkUrl;

  Map<String, dynamic> toJson() => _$SubscribedPodcastToJson(this);

  @override
  List<Object?> get props => [id, title, author, artworkUrl];
}
