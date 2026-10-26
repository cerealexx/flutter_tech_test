import 'package:bloc_test/bloc_test.dart';
import 'package:cabina/common/theme/app_theme.dart';
import 'package:cabina/player/bloc/audio_player_bloc.dart';
import 'package:cabina/player/models/player_position.dart';
import 'package:cabina/player/widgets/seek_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _PlayerBloc extends MockBloc<AudioPlayerEvent, AudioPlayerState>
    implements AudioPlayerBloc {}

void main() {
  late _PlayerBloc bloc;
  const total = Duration(minutes: 20);

  setUpAll(() => registerFallbackValue(const PlayerSeeked(Duration.zero)));
  setUp(() => bloc = _PlayerBloc());

  Future<void> showBar(WidgetTester tester, PlayerPosition position) =>
      tester.pumpWidget(
        BlocProvider<AudioPlayerBloc>.value(
          value: bloc,
          child: MaterialApp(
            theme: AppTheme(isDark: false).toThemeData(),
            home: Scaffold(body: SeekBar(position: position)),
          ),
        ),
      );

  testWidgets('drag previews locally despite incoming playback positions '
      'and seeks only once on release', (tester) async {
    await showBar(
      tester,
      const PlayerPosition(position: Duration(minutes: 1), total: total),
    );
    final slider = find.byType(Slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    final preview = tester.widget<Slider>(slider).value;
    expect(preview, greaterThan(const Duration(minutes: 10).inMilliseconds));
    verifyNever(() => bloc.add(any()));

    // The player keeps ticking while the user holds the thumb still.
    await showBar(
      tester,
      const PlayerPosition(position: Duration(minutes: 2), total: total),
    );
    expect(tester.widget<Slider>(slider).value, preview);
    expect(find.text('2:00'), findsNothing);
    verifyNever(() => bloc.add(any()));

    await gesture.up();
    await tester.pump();
    final event = verify(() => bloc.add(captureAny())).captured.single;
    expect(event, PlayerSeeked(Duration(milliseconds: preview.round())));

    // Once the gesture ends, the bar follows the player's confirmed position.
    await showBar(
      tester,
      const PlayerPosition(position: Duration(minutes: 15), total: total),
    );
    expect(tester.widget<Slider>(slider).value, 900000);
    expect(find.text('15:00'), findsOneWidget);
  });

  testWidgets('a tap also commits one seek', (tester) async {
    await showBar(tester, const PlayerPosition(total: total));
    await tester.tap(find.byType(Slider));
    await tester.pump();

    final event = verify(() => bloc.add(captureAny())).captured.single;
    expect(event, const PlayerSeeked(Duration(minutes: 10)));
  });

  for (final duration in [null, Duration.zero]) {
    testWidgets('cannot seek with duration $duration', (tester) async {
      await showBar(tester, PlayerPosition(total: duration));
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      await tester.tap(find.byType(Slider));
      verifyNever(() => bloc.add(any()));
    });
  }
}
