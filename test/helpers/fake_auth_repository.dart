import 'dart:async';

import 'package:matrix_client/core/architecture/architecture.dart';
import 'package:matrix_client/features/auth/auth_repository.dart';
import 'package:matrix_client/features/auth/session.dart';

const testSession = Session(
  userId: '@alice:matrix.org',
  deviceId: 'DEVICE',
  homeserver: 'https://matrix-client.matrix.org/',
);

typedef LoginCall = ({String homeserver, String username, String password});

final class FakeAuthRepository implements AuthRepository {
  Result<Session> loginResult = const Ok(testSession);
  Completer<Result<Session>>? pendingLogin;
  Result<Session?> restoreResult = const Ok(null);
  Result<LogoutOutcome> logoutResult = const Ok(LogoutOutcome.complete);

  final loginCalls = <LoginCall>[];
  int logoutCalls = 0;

  @override
  Future<Result<Session>> login({
    required String homeserver,
    required String username,
    required String password,
  }) {
    loginCalls.add(
      (homeserver: homeserver, username: username, password: password),
    );
    return pendingLogin?.future ?? Future.value(loginResult);
  }

  @override
  Future<Result<Session?>> restoreSession() async => restoreResult;

  @override
  Future<Result<LogoutOutcome>> logout() async {
    logoutCalls++;
    return logoutResult;
  }
}
