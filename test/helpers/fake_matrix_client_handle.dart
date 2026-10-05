import 'dart:async';

import 'package:matrix_client/src/rust/api/client.dart';
import 'package:matrix_client/src/rust/api/room.dart';
import 'package:matrix_client/src/rust/api/session.dart';

typedef HandleLoginCall = ({
  String homeserver,
  String username,
  String password,
  String dataDir,
  String passphrase,
});

typedef HandleRestoreCall = ({
  SessionDto session,
  String dataDir,
  String passphrase,
});

final class FakeMatrixClientHandle implements MatrixClientHandle {
  Object? loginError;
  Object? restoreError;
  Object? logoutError;
  LogoutOutcomeDto logoutOutcome = LogoutOutcomeDto.complete;

  final loginCalls = <HandleLoginCall>[];
  final restoreCalls = <HandleRestoreCall>[];
  int logoutCalls = 0;
  int stopSyncCalls = 0;

  final roomsController = StreamController<List<RoomDto>>();
  final syncStateController = StreamController<SyncStateDto>();

  @override
  Future<SessionDto> login({
    required String homeserver,
    required String username,
    required String password,
    required String dataDir,
    required String passphrase,
  }) async {
    loginCalls.add((
      homeserver: homeserver,
      username: username,
      password: password,
      dataDir: dataDir,
      passphrase: passphrase,
    ));
    if (loginError case final error?) throw error;
    final number = loginCalls.length;
    return SessionDto(
      homeserver: 'https://matrix-client.matrix.org/',
      userId: '@alice:matrix.org',
      deviceId: 'DEVICE$number',
      accessToken: 'token-$number',
      storeId: 'store$number',
    );
  }

  @override
  Future<void> restoreSession({
    required SessionDto session,
    required String dataDir,
    required String passphrase,
  }) async {
    restoreCalls.add(
      (session: session, dataDir: dataDir, passphrase: passphrase),
    );
    if (restoreError case final error?) throw error;
  }

  @override
  Future<LogoutOutcomeDto> logout() async {
    logoutCalls++;
    if (logoutError case final error?) throw error;
    return logoutOutcome;
  }

  @override
  Stream<List<RoomDto>> rooms() => roomsController.stream;

  @override
  Stream<SyncStateDto> syncState() => syncStateController.stream;

  @override
  Future<void> stopSync() async => stopSyncCalls++;

  @override
  void dispose() {}

  @override
  bool get isDisposed => false;
}
