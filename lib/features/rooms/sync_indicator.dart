import 'package:flutter/material.dart';

import 'rooms_repository.dart';

class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key, required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (color, label) = switch (status) {
      SyncStatus.connected => (colors.primary, 'Conectado'),
      SyncStatus.syncing => (colors.tertiary, 'Sincronizando…'),
      SyncStatus.offline => (colors.outline, 'Offline'),
      SyncStatus.sessionExpired => (colors.error, 'Sessão expirada'),
    };

    return Semantics(
      label: 'Conexão: $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: const SizedBox.square(dimension: 8),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
