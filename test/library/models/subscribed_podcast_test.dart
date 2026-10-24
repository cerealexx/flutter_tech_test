import 'dart:convert';

import 'package:cabina/library/cubit/library_cubit.dart';
import 'package:cabina/library/models/subscribed_podcast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const podcast = SubscribedPodcast(
    id: 7,
    title: 'Café | noticias; 🎧',
    author: 'María; "M" | López',
  );

  test('JSON round trip preserves delimiters, Unicode and null artwork', () {
    final json = jsonDecode(jsonEncode(podcast.toJson()));
    expect(
      SubscribedPodcast.fromJson(json as Map<String, dynamic>),
      podcast,
    );
  });

  test('artwork participates in serialization and equality', () {
    final withArtwork = SubscribedPodcast.fromJson({
      ...podcast.toJson(),
      'artworkUrl': 'https://example.com/art.jpg',
    });
    expect(withArtwork, isNot(podcast));
    expect(withArtwork.toJson()['artworkUrl'], 'https://example.com/art.jpg');
  });

  test('state owns an immutable snapshot of its input list', () {
    final source = [podcast];
    final state = LibraryState(items: source);
    source.clear();

    expect(state.items, [podcast]);
    expect(state.items.clear, throwsUnsupportedError);
  });
}
