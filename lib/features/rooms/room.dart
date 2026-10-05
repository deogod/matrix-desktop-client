enum MessageKind {
  text,
  emote,
  notice,
  image,
  video,
  audio,
  file,
  location,
  sticker,
  encrypted,
  redacted,
  other,
}

final class LastMessage {
  const LastMessage({
    required this.kind,
    required this.isOwn,
    this.senderName,
    this.body,
  });

  final MessageKind kind;
  final bool isOwn;
  final String? senderName;
  final String? body;
}

final class Room {
  const Room({
    required this.id,
    required this.initial,
    this.name,
    this.lastMessage,
    this.lastActivity,
    this.unreadCount = 0,
    this.unreadMentions = 0,
    this.isDirect = false,
  });

  final String id;
  final String? name;
  final String initial;
  final LastMessage? lastMessage;
  final DateTime? lastActivity;
  final int unreadCount;
  final int unreadMentions;
  final bool isDirect;

  bool get hasUnread => unreadCount > 0;

  @override
  bool operator ==(Object other) => other is Room && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
