import 'package:cabina/common/extensions/duration_format.dart';
import 'package:cabina/common/theme/app_theme.dart';
import 'package:cabina/episode_insights/cubit/episode_insights_cubit.dart';
import 'package:cabina/episode_insights/models/episode_insights.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class EpisodeInsightsDrawer extends StatelessWidget {
  const EpisodeInsightsDrawer({
    required this.title,
    required this.cubit,
    required this.onTopic,
    super.key,
  });
  final String title;
  final EpisodeInsightsCubit cubit;
  final void Function(KeyTopic topic, Uri audioUri) onTopic;

  @override
  Widget build(BuildContext context) => Drawer(
    width: MediaQuery.sizeOf(context).width.clamp(0, 420) * 0.92,
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Episode companion',
                    style: AppTextStyles.headline,
                  ),
                ),
                IconButton(
                  tooltip: 'Close summary',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: BlocBuilder<EpisodeInsightsCubit, EpisodeInsightsState>(
              bloc: cubit,
              builder: (context, state) => ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(title, style: AppTextStyles.label),
                  const SizedBox(height: 24),
                  if (state.isBusy) ...[
                    LinearProgressIndicator(
                      value: state.progressPercent / 100,
                      semanticsLabel: 'Generating summary',
                      semanticsValue: '${state.progressPercent}%',
                    ),
                    const SizedBox(height: 16),
                    Text(switch (state.status) {
                      EpisodeInsightsStatus.downloading => 'Downloading audio…',
                      EpisodeInsightsStatus.transcribing ||
                      EpisodeInsightsStatus.summarizing =>
                        'Generating summary... ${state.progressPercent}%',
                      _ => 'Checking saved analysis…',
                    }),
                    const SizedBox(height: 8),
                    const Text(
                      'You can keep listening while our system '
                      'analyzes the episode.',
                    ),
                  ] else if (state.status ==
                      EpisodeInsightsStatus.notConfigured) ...[
                    const Icon(Icons.key_outlined, size: 32),
                    const SizedBox(height: 12),
                    const Text(
                      'AI Companion is not configured for this build.',
                    ),
                  ] else if (state.status == EpisodeInsightsStatus.error) ...[
                    Text(
                      state.errorMessage ?? 'Could not analyze this episode.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: cubit.retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry analysis'),
                    ),
                  ] else if (state.result case final result?) ...[
                    const Text('Summary', style: AppTextStyles.headline),
                    const SizedBox(height: 12),
                    _ExpandableSummary(
                      key: ValueKey(result.insights.summary),
                      text: result.insights.summary,
                    ),
                    const SizedBox(height: 28),
                    const Text('Key topics', style: AppTextStyles.headline),
                    const SizedBox(height: 8),
                    if (result.insights.topics.isEmpty)
                      const Text('No key topics found.'),
                    for (final topic in result.insights.topics)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.play_circle_outline,
                          color: context.appTheme.primary,
                        ),
                        title: Text(topic.title),
                        subtitle: Text(
                          topic.start.clock,
                          style: TextStyle(
                            color: context.appTheme.foregroundSoft,
                          ),
                        ),
                        onTap: () => onTopic(topic, result.audioUri),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Generated with AI · Times may be approximate',
                      style: AppTextStyles.caption.copyWith(
                        color: context.appTheme.foregroundSoft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ExpandableSummary extends StatefulWidget {
  const _ExpandableSummary({required this.text, super.key});

  final String text;

  @override
  State<_ExpandableSummary> createState() => _ExpandableSummaryState();
}

class _ExpandableSummaryState extends State<_ExpandableSummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(
        context,
      ).style.merge(AppTextStyles.body);
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 10,
      )..layout(maxWidth: constraints.maxWidth);
      final canExpand = painter.didExceedMaxLines;
      painter.dispose();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_expanded)
            SelectableText(widget.text, style: style)
          else
            Text(
              widget.text,
              style: style,
              maxLines: 10,
              overflow: TextOverflow.ellipsis,
            ),
          if (canExpand)
            Semantics(
              expanded: _expanded,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: context.appTheme.primary,
                  padding: EdgeInsets.zero,
                  alignment: AlignmentDirectional.centerStart,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'See less' : 'See more'),
              ),
            ),
        ],
      );
    },
  );
}
