import 'package:flutter/material.dart';

import 'room.dart';
import 'room_preview.dart';

class RoomTile extends StatelessWidget {
  const RoomTile({
    super.key,
    required this.room,
    required this.selected,
    required this.onTap,
  });

  final Room room;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final preview = roomPreview(room);

    return ListTile(
      selected: selected,
      selectedTileColor: colors.secondaryContainer,
      selectedColor: colors.onSecondaryContainer,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        child: Text(room.initial),
      ),
      title: Text(
        room.name ?? 'Sala sem nome',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: room.hasUnread
            ? const TextStyle(fontWeight: FontWeight.bold)
            : null,
      ),
      subtitle: preview == null
          ? null
          : Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: _buildTrailing(context),
    );
  }

  Widget? _buildTrailing(BuildContext context) {
    final lastActivity = room.lastActivity;
    if (lastActivity == null && !room.hasUnread) return null;

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasMention = room.unreadMentions > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (lastActivity != null)
          Text(
            activityLabel(lastActivity, now: DateTime.now()),
            style: theme.textTheme.labelSmall,
          ),
        if (room.hasUnread) ...[
          const SizedBox(height: 4),
          Badge(
            backgroundColor: hasMention ? colors.error : colors.primary,
            textColor: hasMention ? colors.onError : colors.onPrimary,
            label: Text(room.unreadCount > 99 ? '99+' : '${room.unreadCount}'),
          ),
        ],
      ],
    );
  }
}
