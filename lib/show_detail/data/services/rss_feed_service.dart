import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/common/network/api_client.dart';
import 'package:cabina/discover/models/podcast.dart';
import 'package:cabina/show_detail/models/episode.dart';
import 'package:cabina/show_detail/models/podcast_detail.dart';
import 'package:xml/xml.dart';

/// Fetches a podcast's RSS feed and turns it into a [PodcastDetail].
class RssFeedService {
  RssFeedService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<PodcastDetail> fetchDetail(Podcast podcast) async {
    final xmlString = await _apiClient.getString(Uri.parse(podcast.feedUrl));
    return _parseFeed(xmlString, podcast);
  }

  PodcastDetail _parseFeed(String xmlString, Podcast podcast) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xmlString);
    } on XmlException catch (e) {
      throw FeedParseException('Feed is not valid XML', cause: e);
    }

    final channel = document.findAllElements('channel').firstOrNull;
    if (channel == null) {
      throw const FeedParseException('Feed is missing a channel');
    }

    final episodes = channel.findAllElements('item').map(_parseEpisode).toList()
      // Newest first.
      ..sort((a, b) {
        final aDate = a.publishedAt ?? DateTime(1970);
        final bDate = b.publishedAt ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });

    final description = _stripHtml(_firstText(channel, 'description') ?? '');

    return PodcastDetail(
      podcastId: podcast.id,
      title: podcast.title,
      author: podcast.author,
      artworkUrl: podcast.artworkUrl,
      descriptionHtml: description,
      episodes: episodes,
    );
  }

  Episode _parseEpisode(XmlElement item) {
    final title = _firstText(item, 'title');
    if (title == null) {
      throw const FeedParseException('An episode is missing its title');
    }

    final audioUrl = _firstAttr(item, 'enclosure', 'url')?.trim();
    if (audioUrl == null || audioUrl.isEmpty) {
      throw const FeedParseException('An episode is missing its audio URL');
    }

    return Episode(
      guid: _firstText(item, 'guid') ?? title,
      title: title,
      audioUrl: audioUrl,
      descriptionHtml: _firstText(item, 'description') ?? '',
      duration: _parseDuration(_firstText(item, 'itunes:duration')),
      publishedAt: _parseDate(_firstText(item, 'pubDate')),
      imageUrl: _firstAttr(item, 'itunes:image', 'href'),
    );
  }

  String? _firstText(XmlElement parent, String name) {
    final matches = parent.findElements(name);
    if (matches.isEmpty) return null;
    final text = matches.first.innerText.trim();
    return text.isEmpty ? null : text;
  }

  String? _firstAttr(XmlElement parent, String name, String attr) {
    final matches = parent.findElements(name);
    if (matches.isEmpty) return null;
    return matches.first.getAttribute(attr);
  }

  Duration? _parseDuration(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length > 3) return null;

    // RSS durations can be seconds, MM:SS, or HH:MM:SS. Invalid optional
    // metadata should not prevent the episode from being played.
    var seconds = 0;
    for (final part in parts) {
      final value = int.tryParse(part, radix: 10);
      if (value == null || value < 0) return null;
      seconds = seconds * 60 + value;
    }
    return Duration(seconds: seconds);
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  String _stripHtml(String html) {
    // Remove tags and collapse whitespace.
    final withoutTags = html.replaceAll(RegExp('<[^>]*>'), ' ');
    return withoutTags.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
