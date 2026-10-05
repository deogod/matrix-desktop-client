import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class StoredSession {
  const StoredSession({
    required this.homeserver,
    required this.userId,
    required this.deviceId,
    required this.accessToken,
    required this.storeId,
    required this.passphrase,
  });

  factory StoredSession.fromJson(Map<String, Object?> json) {
    String field(String name) => switch (json[name]) {
          final String value when value.isNotEmpty => value,
          _ => throw FormatException('Campo ausente na sessão salva: $name'),
        };

    return StoredSession(
      homeserver: field('homeserver'),
      userId: field('userId'),
      deviceId: field('deviceId'),
      accessToken: field('accessToken'),
      storeId: field('storeId'),
      passphrase: field('passphrase'),
    );
  }

  final String homeserver;
  final String userId;
  final String deviceId;
  final String accessToken;
  final String storeId;
  final String passphrase;

  Map<String, String> toJson() => {
        'homeserver': homeserver,
        'userId': userId,
        'deviceId': deviceId,
        'accessToken': accessToken,
        'storeId': storeId,
        'passphrase': passphrase,
      };
}

abstract interface class SessionStore {
  Future<StoredSession?> read();

  Future<void> write(StoredSession session);

  Future<void> clear();
}

final class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage storage = defaultStorage})
      : _storage = storage;

  // The data protection keychain on macOS requires a provisioning profile with
  // keychain-access-groups, which ad hoc signed builds do not have.
  static const defaultStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static const _key = 'matrix_session';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Sessão salva em formato inválido.');
    }
    return StoredSession.fromJson(decoded);
  }

  @override
  Future<void> write(StoredSession session) {
    return _storage.write(key: _key, value: jsonEncode(session.toJson()));
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
