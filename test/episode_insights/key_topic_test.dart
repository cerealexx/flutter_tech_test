import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes segment and numbered prefixes without changing timestamps', () {
    for (final prefix in ['46439_0 — ', '111455782_36 - ', '1 – ', '12 - ']) {
      final topic = KeyTopic.fromJson({
        'title': '${prefix}Host banter',
        'startUs': 46439,
      });
      expect(topic.title, 'Host banter');
      expect(topic.start, const Duration(microseconds: 46439));
    }
  });

  test('preserves meaningful numbers and hyphens within titles', () {
    for (final title in [
      'COVID-19 reflections',
      '3 ways to cook',
      '2026-2027 season',
    ]) {
      expect(KeyTopic.cleanTitle(title), title);
    }
  });
}
