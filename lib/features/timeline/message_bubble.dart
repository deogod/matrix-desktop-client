import 'package:flutter/material.dart';

import '../rooms/room.dart';
import 'timeline_message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.showSender,
  });

  static const _maxWidth = 560.0;

  final TimelineMessage message;
  final bool showSender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isOwn = message.isOwn;
    final (text, isPlaceholder) = _content();
    final textColor =
        isOwn ? colors.onPrimaryContainer : colors.onSurface;

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Padding(
          padding: EdgeInsets.only(top: showSender ? 12 : 2, bottom: 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isOwn
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showSender)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        message.senderName,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: colors.primary),
                      ),
                    ),
                  SelectableText(
                    text,
                    style: isPlaceholder
                        ? theme.textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: colors.onSurfaceVariant,
                          )
                        : theme.textTheme.bodyMedium?.copyWith(color: textColor),
                  ),
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerRight,
                    widthFactor: 1,
                    child: _buildFooter(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labelStyle =
        theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_timeLabel(message.timestamp, DateTime.now()), style: labelStyle),
        if (message.sendStatus == SendStatus.sending) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: 'Enviando',
            child: Icon(Icons.schedule, size: 12, color: colors.onSurfaceVariant),
          ),
        ],
        if (message.sendStatus == SendStatus.failed) ...[
          const SizedBox(width: 4),
          Icon(Icons.error_outline, size: 14, color: colors.error),
          const SizedBox(width: 2),
          Text(
            'Não enviada',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.error),
          ),
        ],
      ],
    );
  }

  (String, bool) _content() {
    final body = message.body;
    return switch (message.kind) {
      MessageKind.text || MessageKind.notice => (body ?? '', false),
      MessageKind.emote => ('* ${message.senderName} ${body ?? ''}', false),
      MessageKind.image => ('Imagem', true),
      MessageKind.video => ('Vídeo', true),
      MessageKind.audio => ('Áudio', true),
      MessageKind.file => ('Arquivo', true),
      MessageKind.location => ('Localização', true),
      MessageKind.sticker => ('Figurinha', true),
      MessageKind.encrypted => (_undecryptableText(), true),
      MessageKind.redacted => ('Mensagem apagada', true),
      MessageKind.other => body == null
          ? ('Mensagem não suportada', true)
          : (body, false),
    };
  }

  String _undecryptableText() => switch (message.undecryptableReason) {
        UndecryptableReason.sentBeforeJoined =>
          'Mensagem enviada antes de você entrar na sala.',
        UndecryptableReason.historyUnavailable =>
          'Histórico indisponível neste dispositivo.',
        UndecryptableReason.unverifiedDevice =>
          'O remetente não compartilha mensagens com dispositivos não '
              'verificados.',
        UndecryptableReason.withheldBySender =>
          'O remetente não compartilhou esta mensagem com este dispositivo.',
        UndecryptableReason.untrustedSender =>
          'Mensagem de um dispositivo não confiável.',
        UndecryptableReason.unknown ||
        null =>
          'Não foi possível descriptografar esta mensagem.',
      };

  static String _timeLabel(DateTime timestamp, DateTime now) {
    final local = timestamp.toLocal();
    final time = '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (isToday) return time;
    return '${_twoDigits(local.day)}/${_twoDigits(local.month)} $time';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
