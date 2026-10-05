import 'package:flutter/material.dart';

import '../../core/architecture/architecture.dart';
import '../rooms/room.dart';
import 'timeline_bloc.dart';
import 'timeline_stable_state.dart';

class TimelinePanel extends ScreenView<TimelineBloc> {
  const TimelinePanel({super.key, required this.room});

  final Room room;

  @override
  TimelineBloc createBloc() => TimelineBloc(
        roomId: room.id,
        timelineRepository: Locator.instance.get(),
      );

  @override
  Widget build(BuildContext context, TimelineBloc bloc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        const Divider(height: 1),
        Expanded(
          child: ScreenStateBuilder(
            bloc: bloc,
            onStable: (context, data) => TimelineStableState(
              bloc: bloc,
              data: data,
              showSenderNames: !room.isDirect,
            ),
            onError: (context, failure) => _buildError(context, failure),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Text(
        room.name ?? 'Sala sem nome',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _buildError(BuildContext context, Failure failure) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Não foi possível abrir a conversa.\n${failure.message}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
