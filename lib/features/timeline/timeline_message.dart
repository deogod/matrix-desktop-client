import '../rooms/room.dart';

enum SendStatus { sending, sent, failed }

enum UndecryptableReason {
  unknown,
  sentBeforeJoined,
  historyUnavailable,
  unverifiedDevice,
  withheldBySender,
  untrustedSender,
}

final class TimelineMessage {
  const TimelineMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.kind,
    required this.timestamp,
    this.body,
    this.undecryptableReason,
    this.isOwn = false,
    this.sendStatus = SendStatus.sent,
  });

  final String id;
  final String senderId;
  final String senderName;
  final MessageKind kind;
  final DateTime timestamp;
  final String? body;
  final UndecryptableReason? undecryptableReason;
  final bool isOwn;
  final SendStatus sendStatus;

  @override
  bool operator ==(Object other) => other is TimelineMessage && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
