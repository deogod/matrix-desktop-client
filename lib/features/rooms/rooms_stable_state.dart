import 'package:flutter/material.dart';

import '../../core/architecture/architecture.dart';
import '../timeline/timeline_panel.dart';
import 'room_tile.dart';
import 'rooms_bloc.dart';
import 'rooms_repository.dart';
import 'sync_indicator.dart';

class RoomsStableState extends StatelessWidget {
  const RoomsStableState({super.key, required this.bloc, required this.data});

  static const _listWidth = 320.0;

  final RoomsBloc bloc;
  final RoomsStableData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: _listWidth, child: _buildListPanel(context)),
        const VerticalDivider(width: 1),
        Expanded(child: _buildRoomPanel(context)),
      ],
    );
  }

  Widget _buildListPanel(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Salas', style: textTheme.titleLarge),
        ),
        Expanded(child: data.isEmpty ? _buildEmptyList(context) : _buildList()),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SyncIndicator(status: data.syncStatus),
              const Spacer(),
              PersistentButton(
                bloc: bloc,
                onPressed: () => bloc.dispatchEvent(RoomsLogoutEvent()),
                child: const Text('Sair'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
      itemCount: data.rooms.length,
      itemBuilder: (context, index) {
        final room = data.rooms[index];
        return RoomTile(
          key: ValueKey(room.id),
          room: room,
          selected: room.id == data.selectedRoomId,
          onTap: () => bloc.dispatchEvent(RoomsSelectEvent(room.id)),
        );
      },
    );
  }

  Widget _buildEmptyList(BuildContext context) {
    final theme = Theme.of(context);
    final isLoading = data.syncStatus == SyncStatus.syncing;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              isLoading ? 'Carregando salas…' : 'Nenhuma sala ainda.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The key recreates the panel and its bloc when another room is selected.
  Widget _buildRoomPanel(BuildContext context) {
    final room = data.selectedRoom;
    return room == null
        ? _buildPlaceholder(context)
        : TimelinePanel(key: ValueKey(room.id), room: room);
  }

  Widget _buildPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 48, color: colors.outline),
          const SizedBox(height: 16),
          Text(
            'Selecione uma sala',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
