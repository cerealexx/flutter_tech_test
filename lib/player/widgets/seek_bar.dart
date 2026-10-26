import 'package:cabina/common/extensions/duration_format.dart';
import 'package:cabina/common/theme/app_theme.dart';
import 'package:cabina/player/bloc/audio_player_bloc.dart';
import 'package:cabina/player/models/player_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SeekBar extends StatefulWidget {
  const SeekBar({required this.position, super.key});

  final PlayerPosition position;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final total = widget.position.total ?? Duration.zero;
    final maxMs = total.inMilliseconds.toDouble();
    final valueMs =
        (_dragValue ?? widget.position.position.inMilliseconds.toDouble())
            .clamp(0.0, maxMs);

    return Column(
      children: [
        Slider(
          value: maxMs == 0 ? 0 : valueMs,
          max: maxMs == 0 ? 1 : maxMs,
          activeColor: theme.primary,
          onChanged: maxMs == 0
              ? null
              : (value) => setState(() => _dragValue = value),
          onChangeEnd: maxMs == 0
              ? null
              : (value) {
                  context.read<AudioPlayerBloc>().add(
                    PlayerSeeked(Duration(milliseconds: value.round())),
                  );
                  setState(() => _dragValue = null);
                },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                Duration(milliseconds: valueMs.round()).clock,
                style: AppTextStyles.caption,
              ),
              Text(total.clock, style: AppTextStyles.caption),
            ],
          ),
        ),
      ],
    );
  }
}
