import 'dart:convert';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../../core/architecture/architecture.dart';
import '../../core/failure_mapper.dart';
import '../../src/rust/api/client.dart';
import '../../src/rust/api/error.dart';
import '../../src/rust/api/session.dart';
import 'session.dart';
import 'session_store.dart';

enum LogoutOutcome { complete, localOnly }

abstract interface class AuthRepository {
  Future<Result<Session>> login({
    required String homeserver,
    required String username,
    required String password,
  });

  Future<Result<Session?>> restoreSession();

  Future<Result<LogoutOutcome>> logout();
}

final class MatrixAuthRepository implements AuthRepository {
  MatrixAuthRepository({
    required MatrixClientHandle handle,
    required SessionStore store,
    Future<String> Function() dataDirectory = _applicationSupportPath,
    String Function() generatePassphrase = _randomPassphrase,
  })  : _handle = handle,
        _store = store,
        _dataDirectory = dataDirectory,
        _generatePassphrase = generatePassphrase;

  final MatrixClientHandle _handle;
  final SessionStore _store;
  final Future<String> Function() _dataDirectory;
  final String Function() _generatePassphrase;

  @override
  Future<Result<Session>> login({
    required String homeserver,
    required String username,
    required String password,
  }) {
    return guard(() async {
      final passphrase = _generatePassphrase();
      final dto = await _handle.login(
        homeserver: homeserver,
        username: username,
        password: password,
        dataDir: await _dataDirectory(),
        passphrase: passphrase,
      );
      // The saved session is only replaced after the new login succeeds.
      try {
        await _store.write(_toStoredSession(dto, passphrase));
      } catch (_) {
        await _discardLogin();
        rethrow;
      }
      return _toSession(dto);
    }, onError: mapFailure);
  }

  @override
  Future<Result<Session?>> restoreSession() {
    return guard(() async {
      final stored = await _readStoredSession();
      if (stored == null) return null;

      final dto = _toSessionDto(stored);
      try {
        await _handle.restoreSession(
          session: dto,
          dataDir: await _dataDirectory(),
          passphrase: stored.passphrase,
        );
      } on MatrixError catch (error) {
        if (_endsSession(error)) await _store.clear();
        rethrow;
      }
      return _toSession(dto);
    }, onError: mapFailure);
  }

  @override
  Future<Result<LogoutOutcome>> logout() {
    return guard(() async {
      try {
        return _toLogoutOutcome(await _handle.logout());
      } finally {
        await _store.clear();
      }
    }, onError: mapFailure);
  }

  Future<StoredSession?> _readStoredSession() async {
    try {
      return await _store.read();
    } on FormatException {
      await _store.clear();
      rethrow;
    }
  }

  // Without the saved session this login could never be restored, so it is
  // closed instead of left active on the server. The write failure is the one
  // reported to the user.
  Future<void> _discardLogin() async {
    try {
      await _handle.logout();
    } catch (_) {
      // Ignored on purpose, see above.
    }
  }

  // Network and unknown failures keep the saved session for the next attempt.
  static bool _endsSession(MatrixError error) => switch (error) {
        MatrixError.sessionExpired ||
        MatrixError.storage ||
        MatrixError.invalidHomeserver ||
        MatrixError.unsupportedHomeserver =>
          true,
        MatrixError.network ||
        MatrixError.unknown ||
        MatrixError.invalidCredentials =>
          false,
      };
}

Future<String> _applicationSupportPath() async {
  final directory = await getApplicationSupportDirectory();
  return directory.path;
}

String _randomPassphrase() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes);
}

Session _toSession(SessionDto dto) => Session(
      userId: dto.userId,
      deviceId: dto.deviceId,
      homeserver: dto.homeserver,
    );

StoredSession _toStoredSession(SessionDto dto, String passphrase) =>
    StoredSession(
      homeserver: dto.homeserver,
      userId: dto.userId,
      deviceId: dto.deviceId,
      accessToken: dto.accessToken,
      storeId: dto.storeId,
      passphrase: passphrase,
    );

SessionDto _toSessionDto(StoredSession stored) => SessionDto(
      homeserver: stored.homeserver,
      userId: stored.userId,
      deviceId: stored.deviceId,
      accessToken: stored.accessToken,
      storeId: stored.storeId,
    );

LogoutOutcome _toLogoutOutcome(LogoutOutcomeDto dto) => switch (dto) {
      LogoutOutcomeDto.complete => LogoutOutcome.complete,
      LogoutOutcomeDto.localOnly => LogoutOutcome.localOnly,
    };
