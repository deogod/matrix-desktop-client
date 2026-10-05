import 'package:flutter/material.dart';

import 'message_bubble.dart';
import 'message_composer.dart';
import 'timeline_bloc.dart';
import 'timeline_message.dart';

class TimelineStableState extends StatefulWidget {
  const TimelineStableState({
    super.key,
    required this.bloc,
    required this.data,
    required this.showSenderNames,
  });

  final TimelineBloc bloc;
  final TimelineStableData data;
  final bool showSenderNames;

  @override
  State<TimelineStableState> createState() => _TimelineStableStateState();
}

class _TimelineStableStateState extends State<TimelineStableState> {
  static const _loadOlderThreshold = 300.0;

  final _scrollController = ScrollController();
  bool _wasNearTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // The list is reversed, so the end of the scroll extent is the top. Older
  // messages are requested once each time the user gets close to it.
  void _onScroll() {
    final isNearTop =
        _scrollController.position.extentAfter < _loadOlderThreshold;
    if (isNearTop && !_wasNearTop) {
      widget.bloc.dispatchEvent(TimelineLoadOlderEvent());
    }
    _wasNearTop = isNearTop;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: widget.data.isEmpty ? _buildEmpty(context) : _buildList(),
        ),
        const Divider(height: 1),
        MessageComposer(bloc: widget.bloc),
      ],
    );
  }

  // Reversed so that the newest message sits at the bottom, new messages keep
  // the view at the bottom only when it is already there, and older pages are
  // added above without moving what is on screen.
  Widget _buildList() {
    final messages = widget.data.messages;
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index == messages.length) return _buildHistoryEdge(context);

        final message = messages[messages.length - 1 - index];
        final older = index + 1 < messages.length
            ? messages[messages.length - 2 - index]
            : null;
        return MessageBubble(
          key: ValueKey(message.id),
          message: message,
          showSender: _showSender(message, older),
        );
      },
    );
  }

  bool _showSender(TimelineMessage message, TimelineMessage? older) {
    return widget.showSenderNames &&
        !message.isOwn &&
        older?.senderId != message.senderId;
  }

  Widget _buildHistoryEdge(BuildContext context) {
    if (widget.data.isLoadingOlder) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (widget.data.reachedStart) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Início da conversa',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return const SizedBox(height: 12);
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.data.isLoadingOlder) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Text(
        'Nenhuma mensagem ainda.',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
