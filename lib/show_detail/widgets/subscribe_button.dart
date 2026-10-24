import 'dart:async';

import 'package:cabina/home/home_page.dart';
import 'package:cabina/library/cubit/library_cubit.dart';
import 'package:cabina/library/models/subscribed_podcast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class SubscribeButton extends StatefulWidget {
  const SubscribeButton({
    required this.id,
    required this.title,
    required this.author,
    this.artworkUrl,
    super.key,
  });

  final int id;
  final String title;
  final String author;
  final String? artworkUrl;

  @override
  State<SubscribeButton> createState() => _SubscribeButtonState();
}

class _SubscribeButtonState extends State<SubscribeButton> {
  Timer? _throttle;

  Future<void> _onPressed(BuildContext context) async {
    if (_throttle?.isActive ?? false) return;
    _throttle = Timer(const Duration(milliseconds: 300), () {});

    final libraryCubit = context.read<LibraryCubit>();
    final state = libraryCubit.state;

    if (state.isSubscribed(widget.id)) {
      return libraryCubit.unsubscribe(widget.id);
    }

    return libraryCubit.subscribe(
      SubscribedPodcast(
        id: widget.id,
        title: widget.title,
        author: widget.author,
        artworkUrl: widget.artworkUrl,
      ),
    );
  }

  @override
  void dispose() {
    _throttle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        if (state.status == LibraryStatus.error) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Unexpected library error.'),
              TextButton(
                onPressed: () => context.goNamed(
                  HomePage.routeName,
                  queryParameters: {'tab': 'library'},
                ),
                child: const Text(
                  'Open library',
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
              ),
            ],
          );
        }

        final loading =
            state.status == LibraryStatus.initial ||
            state.status == LibraryStatus.loading;
        final subscriptionStatus = state.isSubscribed(widget.id)
            ? _SubscriptionStatus.subscribed
            : _SubscriptionStatus.unsubscribed;
        final error = state.failedPodcastId == widget.id
            ? state.errorMessage
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            FilledButton.icon(
              style: loading
                  ? FilledButton.styleFrom(
                      disabledBackgroundColor: colorScheme.primary,
                      disabledForegroundColor: colorScheme.onPrimary,
                    )
                  : null,
              onPressed: loading ? null : () => _onPressed(context),
              icon: loading
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : Icon(subscriptionStatus.icon),
              label: Text(
                loading ? 'Loading library…' : subscriptionStatus.label,
              ),
            ),
            if (error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

enum _SubscriptionStatus {
  subscribed('Unsubscribe', Icons.check),
  unsubscribed('Subscribe', Icons.add);

  const _SubscriptionStatus(this.label, this.icon);

  final String label;
  final IconData icon;
}
