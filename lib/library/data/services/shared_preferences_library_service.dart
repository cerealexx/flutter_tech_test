import 'dart:convert';

import 'package:cabina/common/errors/exceptions.dart';
import 'package:cabina/library/data/services/i_library_service.dart';
import 'package:cabina/library/models/subscribed_podcast.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesLibraryService implements ILibraryService {
  SharedPreferencesLibraryService({required SharedPreferences prefs})
    : _prefs = prefs;

  static const _key = 'library_podcasts';

  final SharedPreferences _prefs;
  bool _loaded = false;
  bool _needsReload = false;
  Future<void>? _reloadFuture;

  @override
  Future<List<SubscribedPodcast>> load() async {
    _loaded = false;
    try {
      await _reloadIfNeeded();
      final items = _read();
      _loaded = true;
      return List.unmodifiable(items);
    } on Exception catch (error) {
      throw LibraryStorageException(
        'Could not load your library. Please try again.',
        cause: error,
      );
    }
  }

  @override
  Future<void> subscribe(SubscribedPodcast podcast) => _update((items) {
    if (items.any((item) => item.id == podcast.id)) return items;
    return [...items, podcast];
  });

  @override
  Future<void> unsubscribe(int podcastId) => _update((items) {
    if (!items.any((item) => item.id == podcastId)) return items;
    return items.where((item) => item.id != podcastId).toList();
  });

  Future<void> _update(
    List<SubscribedPodcast> Function(List<SubscribedPodcast>) update,
  ) async {
    if (!_loaded) {
      throw const LibraryStorageException(
        'Load your library before changing subscriptions.',
      );
    }
    try {
      await _reloadIfNeeded();
      final items = _read();
      final updated = update(items);
      if (identical(updated, items)) return;

      // setString updates the cache synchronously. Keep the read and write
      // together so the next operation sees this change before it is persisted.
      final saved = await _prefs.setString(
        _key,
        jsonEncode(updated.map((item) => item.toJson()).toList()),
      );
      if (!saved) {
        throw const LibraryStorageException('The storage write failed.');
      }
    } on Exception catch (error) {
      _needsReload = true;
      throw LibraryStorageException(
        'Could not save your library. Please try again.',
        cause: error,
      );
    }
  }

  Future<void> _reloadIfNeeded() async {
    if (!_needsReload) return;
    // Concurrent retries share one refresh, so a later refresh cannot replace
    // the cache after another retry has already updated it.
    final reload = _reloadFuture ??= _prefs.reload();
    try {
      await reload;
      _needsReload = false;
    } finally {
      _reloadFuture = null;
    }
  }

  List<SubscribedPodcast> _read() {
    final raw = _prefs.get(_key);
    if (raw == null) return [];
    if (raw is! String) {
      throw const FormatException('Invalid library storage type');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Invalid library format');
    }
    final items = <SubscribedPodcast>[];
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic> ||
          entry['id'] is! int ||
          entry['title'] is! String ||
          entry['author'] is! String ||
          (entry['artworkUrl'] != null && entry['artworkUrl'] is! String)) {
        throw const FormatException('Invalid library subscription');
      }
      items.add(SubscribedPodcast.fromJson(entry));
    }
    return items;
  }
}
