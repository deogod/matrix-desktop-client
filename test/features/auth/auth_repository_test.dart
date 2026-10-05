import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/core/architecture/architecture.dart';
import 'package:matrix_client/features/auth/auth_repository.dart';
import 'package:matrix_client/features/auth/session.dart';
import 'package:matrix_client/features/auth/session_store.dart';
import 'package:matrix_client/src/rust/api/error.dart';
import 'package:matrix_client/src/rust/api/session.dart';

import '../../helpers/fake_matrix_client_handle.dart';

final class FakeSessionStore implements SessionStore {
  StoredSession? session;
  Object? readError;
  Object? writeError;
  int clearCalls = 0;

  @override
  Future<StoredSession?> read() async {
    if (readError case final error?) throw error;
    return session;
  }

  @override
  Future<void> write(StoredSession session) async {
    if (writeError case final error?) throw error;
    this.session = session;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    session = null;
  }
}

const savedSession = StoredSession(
  homeserver: 'https://matrix-client.matrix.org/',
  userId: '@bob:matrix.org',
  deviceId: 'SAVEDDEVICE',
  accessToken: 'saved-token',
  storeId: 'savedstore',
  passphrase: 'saved-passphrase',
);

Matcher isOk(Object? value) =>
    isA<Ok<dynamic>>().having((result) => result.value, 'value', value);

Matcher isErr<F extends Failure>() => isA<Err<dynamic>>()
    .having((result) => result.failure, 'failure', isA<F>());

void main() {
  late FakeMatrixClientHandle handle;
  late FakeSessionStore store;
  late MatrixAuthRepository repository;
  late int passphrases;

  setUp(() {
    handle = FakeMatrixClientHandle();
    store = FakeSessionStore();
    passphrases = 0;
    repository = MatrixAuthRepository(
      handle: handle,
      store: store,
      dataDirectory: () async => '/app-support',
      generatePassphrase: () => 'passphrase-${++passphrases}',
    );
  });

  Future<Result<Session>> login() => repository.login(
        homeserver: 'matrix.org',
        username: 'alice',
        password: 'senha',
      );

  group('login', () {
    test('passa credenciais, diretório e uma passphrase nova ao handle',
        () async {
      await login();

      expect(handle.loginCalls, [
        (
          homeserver: 'matrix.org',
          username: 'alice',
          password: 'senha',
          dataDir: '/app-support',
          passphrase: 'passphrase-1',
        ),
      ]);
    });

    test('salva token, store e passphrase e devolve a sessão sem token',
        () async {
      final result = await login();

      expect(
        result,
        isOk(
          const Session(
            userId: '@alice:matrix.org',
            deviceId: 'DEVICE1',
            homeserver: 'https://matrix-client.matrix.org/',
          ),
        ),
      );
      expect(store.session?.accessToken, 'token-1');
      expect(store.session?.storeId, 'store1');
      expect(store.session?.passphrase, 'passphrase-1');
    });

    test('gera uma passphrase nova a cada login', () async {
      await login();
      await login();

      expect(
        handle.loginCalls.map((call) => call.passphrase),
        ['passphrase-1', 'passphrase-2'],
      );
      expect(store.session?.passphrase, 'passphrase-2');
    });

    test('falha não apaga nem sobrescreve a sessão salva', () async {
      store.session = savedSession;
      handle.loginError = MatrixError.invalidCredentials;

      final result = await login();

      expect(result, isErr<InvalidCredentialsFailure>());
      expect(store.session, same(savedSession));
      expect(store.clearCalls, 0);
    });

    test('converte cada MatrixError na falha correspondente', () async {
      final expected = <MatrixError, Matcher>{
        MatrixError.invalidCredentials: isErr<InvalidCredentialsFailure>(),
        MatrixError.invalidHomeserver: isErr<InvalidHomeserverFailure>(),
        MatrixError.network: isErr<NetworkFailure>(),
        MatrixError.sessionExpired: isErr<SessionExpiredFailure>(),
        MatrixError.storage: isErr<StorageFailure>(),
        MatrixError.unsupportedHomeserver: isErr<InvalidHomeserverFailure>(),
        MatrixError.unknown: isErr<UnknownFailure>(),
      };

      for (final MapEntry(key: error, value: matcher) in expected.entries) {
        handle.loginError = error;
        expect(await login(), matcher, reason: '$error');
      }
    });

    test('se não conseguir salvar, encerra o login no handle', () async {
      store.writeError = PlatformException(code: 'keychain');

      final result = await login();

      expect(result, isErr<StorageFailure>());
      expect(handle.logoutCalls, 1);
    });

    test('aceita novo login depois do logout', () async {
      expect(await login(), isA<Ok<Session>>());
      expect(await repository.logout(), isOk(LogoutOutcome.complete));

      final result = await login();

      expect(result, isA<Ok<Session>>());
      expect(handle.loginCalls, hasLength(2));
      expect(store.session?.storeId, 'store2');
    });
  });

  group('restoreSession', () {
    test('sem sessão salva devolve null e não chama o handle', () async {
      final result = await repository.restoreSession();

      expect(result, isOk(null));
      expect(handle.restoreCalls, isEmpty);
    });

    test('usa homeserver, store e passphrase salvos', () async {
      store.session = savedSession;

      final result = await repository.restoreSession();

      expect(
        result,
        isOk(
          const Session(
            userId: '@bob:matrix.org',
            deviceId: 'SAVEDDEVICE',
            homeserver: 'https://matrix-client.matrix.org/',
          ),
        ),
      );
      final call = handle.restoreCalls.single;
      expect(call.session.homeserver, savedSession.homeserver);
      expect(call.session.accessToken, savedSession.accessToken);
      expect(call.session.storeId, savedSession.storeId);
      expect(call.passphrase, savedSession.passphrase);
      expect(call.dataDir, '/app-support');
    });

    test('falha de rede ou desconhecida mantém a sessão salva', () async {
      for (final error in [MatrixError.network, MatrixError.unknown]) {
        store.session = savedSession;
        handle.restoreError = error;

        await repository.restoreSession();

        expect(store.session, same(savedSession), reason: '$error');
      }
      expect(store.clearCalls, 0);
    });

    test('sessão expirada, store indisponível ou servidor inválido apagam a '
        'sessão salva', () async {
      final expected = <MatrixError, Matcher>{
        MatrixError.sessionExpired: isErr<SessionExpiredFailure>(),
        MatrixError.storage: isErr<StorageFailure>(),
        MatrixError.invalidHomeserver: isErr<InvalidHomeserverFailure>(),
      };

      for (final MapEntry(key: error, value: matcher) in expected.entries) {
        store.session = savedSession;
        handle.restoreError = error;

        expect(await repository.restoreSession(), matcher, reason: '$error');
        expect(store.session, isNull, reason: '$error');
      }
    });

    test('sessão salva corrompida é apagada', () async {
      store.readError = const FormatException('corrompida');

      final result = await repository.restoreSession();

      expect(result, isErr<StorageFailure>());
      expect(store.clearCalls, 1);
      expect(handle.restoreCalls, isEmpty);
    });
  });

  group('logout', () {
    test('devolve complete e apaga a sessão salva', () async {
      store.session = savedSession;

      final result = await repository.logout();

      expect(result, isOk(LogoutOutcome.complete));
      expect(store.session, isNull);
    });

    test('devolve localOnly quando o servidor não foi avisado', () async {
      handle.logoutOutcome = LogoutOutcomeDto.localOnly;

      expect(await repository.logout(), isOk(LogoutOutcome.localOnly));
    });

    test('apaga a sessão salva mesmo quando o handle falha', () async {
      store.session = savedSession;
      handle.logoutError = MatrixError.storage;

      final result = await repository.logout();

      expect(result, isErr<StorageFailure>());
      expect(store.session, isNull);
    });
  });
}
