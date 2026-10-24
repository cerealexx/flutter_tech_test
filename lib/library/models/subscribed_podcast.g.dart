// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subscribed_podcast.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SubscribedPodcast _$SubscribedPodcastFromJson(Map<String, dynamic> json) =>
    SubscribedPodcast(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      author: json['author'] as String,
      artworkUrl: json['artworkUrl'] as String?,
    );

Map<String, dynamic> _$SubscribedPodcastToJson(SubscribedPodcast instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'author': instance.author,
      'artworkUrl': instance.artworkUrl,
    };
