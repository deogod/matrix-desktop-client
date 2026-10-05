final class Session {
  const Session({
    required this.userId,
    required this.deviceId,
    required this.homeserver,
  });

  final String userId;
  final String deviceId;
  final String homeserver;

  @override
  bool operator ==(Object other) =>
      other is Session && other.userId == userId && other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(userId, deviceId);
}
