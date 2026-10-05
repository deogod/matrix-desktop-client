import 'room.dart';

String? roomPreview(Room room) {
  final message = room.lastMessage;
  if (message == null) return null;

  final content = switch (message.kind) {
    MessageKind.text || MessageKind.notice || MessageKind.emote =>
      message.body ?? '',
    MessageKind.image => 'Imagem',
    MessageKind.video => 'Vídeo',
    MessageKind.audio => 'Áudio',
    MessageKind.file => 'Arquivo',
    MessageKind.location => 'Localização',
    MessageKind.sticker => 'Figurinha',
    MessageKind.encrypted => 'Mensagem criptografada',
    MessageKind.redacted => 'Mensagem apagada',
    MessageKind.other => message.body ?? 'Mensagem',
  };
  final author = message.isOwn ? 'Você' : message.senderName;

  if (message.kind == MessageKind.emote) {
    return ['*', ?author, content].join(' ');
  }
  if (message.isOwn) return 'Você: $content';
  // When the room is a direct chat, or is named after the sender (a two-person
  // room not marked as direct), the room name already says who wrote it.
  if (room.isDirect || author == null || author == room.name) return content;
  return '$author: $content';
}

String activityLabel(DateTime time, {required DateTime now}) {
  final local = time.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);

  if (day == today) {
    return '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
  }
  if (day == today.subtract(const Duration(days: 1))) return 'Ontem';
  if (local.year == now.year) {
    return '${_twoDigits(local.day)}/${_twoDigits(local.month)}';
  }
  return '${_twoDigits(local.day)}/${_twoDigits(local.month)}/'
      '${_twoDigits(local.year % 100)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
