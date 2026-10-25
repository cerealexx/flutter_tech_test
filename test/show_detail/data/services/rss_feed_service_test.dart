import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/common/network/api_client.dart';
import 'package:cabina/discover/models/podcast.dart';
import 'package:cabina/show_detail/data/services/rss_feed_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockApiClient extends Mock implements ApiClient {}

String _feed(String? duration) =>
    '''
<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <item>
      <guid>episode-1</guid>
      <title>Episode one</title>
      <enclosure url="https://example.com/episode.mp3" type="audio/mpeg" />
      ${duration == null ? '' : '<itunes:duration>$duration</itunes:duration>'}
    </item>
  </channel>
</rss>
''';

void main() {
  late _MockApiClient apiClient;
  late RssFeedService service;
  const podcast = Podcast(
    id: 1503869154,
    title: 'The Top Chef After Show Podcast',
    author: 'AfterBuzz TV',
    feedUrl: 'https://example.com/feed.xml',
  );
  final feedUri = Uri.parse(podcast.feedUrl);

  setUp(() {
    apiClient = _MockApiClient();
    service = RssFeedService(apiClient: apiClient);
  });

  group('RssFeedService durations', () {
    const validDurations = {
      // Seconds-only format from the Top Chef feed that caused a RangeError.
      '3173': Duration(minutes: 52, seconds: 53),
      '52:53': Duration(minutes: 52, seconds: 53),
      '00:52:53': Duration(minutes: 52, seconds: 53),
      '1:02:03': Duration(hours: 1, minutes: 2, seconds: 3),
      '65:03': Duration(hours: 1, minutes: 5, seconds: 3),
      ' 3173 ': Duration(minutes: 52, seconds: 53),
      '0': Duration.zero,
    };
    for (final entry in validDurations.entries) {
      test('parses ${entry.key}', () async {
        when(() => apiClient.getString(feedUri)).thenAnswer(
          (_) async => _feed(entry.key),
        );

        final detail = await service.fetchDetail(podcast);

        expect(detail.episodes.single.duration, entry.value);
        expect(
          detail.episodes.single.audioUrl,
          'https://example.com/episode.mp3',
        );
      });
    }

    for (final raw in [
      null,
      '',
      'unknown',
      '-1',
      '1:-2:03',
      '1::03',
      '1:2:3:4',
    ]) {
      test('keeps the episode when duration is $raw', () async {
        when(() => apiClient.getString(feedUri)).thenAnswer(
          (_) async => _feed(raw),
        );

        final detail = await service.fetchDetail(podcast);

        expect(detail.episodes.single.duration, isNull);
        expect(detail.episodes.single.title, 'Episode one');
      });
    }
  });

  test('reports malformed XML as a feed error', () async {
    when(() => apiClient.getString(feedUri)).thenAnswer(
      (_) async => '<rss><channel>',
    );

    await expectLater(
      service.fetchDetail(podcast),
      throwsA(isA<FeedParseException>()),
    );
  });

  group('required RSS fields', () {
    final validFeed = _feed('3173');
    const title = '<title>Episode one</title>';
    const enclosure =
        '<enclosure url="https://example.com/episode.mp3" type="audio/mpeg" />';
    final invalidFeeds = {
      'missing channel': (
        '<rss />',
        'Feed is missing a channel',
      ),
      'missing title even when guid is present': (
        validFeed.replaceFirst(title, ''),
        'An episode is missing its title',
      ),
      'empty title': (
        validFeed.replaceFirst(title, '<title />'),
        'An episode is missing its title',
      ),
      'blank title': (
        validFeed.replaceFirst(title, '<title>   </title>'),
        'An episode is missing its title',
      ),
      'missing enclosure': (
        validFeed.replaceFirst(enclosure, ''),
        'An episode is missing its audio URL',
      ),
      'missing audio URL': (
        validFeed.replaceFirst(enclosure, '<enclosure type="audio/mpeg" />'),
        'An episode is missing its audio URL',
      ),
      'empty audio URL': (
        validFeed.replaceFirst(enclosure, '<enclosure url="" />'),
        'An episode is missing its audio URL',
      ),
      'blank audio URL': (
        validFeed.replaceFirst(enclosure, '<enclosure url="   " />'),
        'An episode is missing its audio URL',
      ),
    };

    for (final entry in invalidFeeds.entries) {
      test('reports ${entry.key} as a feed error', () async {
        final (xml, message) = entry.value;
        when(() => apiClient.getString(feedUri)).thenAnswer((_) async => xml);

        await expectLater(
          service.fetchDetail(podcast),
          throwsA(
            isA<FeedParseException>().having(
              (error) => error.message,
              'message',
              message,
            ),
          ),
        );
      });
    }

    test('accepts a channel with no episodes', () async {
      when(() => apiClient.getString(feedUri)).thenAnswer(
        (_) async => '<rss><channel /></rss>',
      );

      final detail = await service.fetchDetail(podcast);

      expect(detail.episodes, isEmpty);
      expect(detail.title, podcast.title);
      expect(detail.author, podcast.author);
    });

    for (final guid in ['', '<guid>   </guid>']) {
      test('uses the title when guid is absent or blank: $guid', () async {
        when(() => apiClient.getString(feedUri)).thenAnswer(
          (_) async => validFeed.replaceFirst('<guid>episode-1</guid>', guid),
        );

        final detail = await service.fetchDetail(podcast);

        expect(detail.episodes.single.guid, 'Episode one');
      });
    }
  });
}
