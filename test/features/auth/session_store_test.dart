import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/features/auth/session_store.dart';

const session = StoredSession(
  homeserver: 'https://matrix-client.matrix.org/',
  userId: '@alice:matrix.org',
  deviceId: 'DEVICE',
  accessToken: 'token',
  storeId: 'store',
  passphrase: 'passphrase',
);

void main() {
  late SecureSessionStore store;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = SecureSessionStore();
  });

  test('sem sessão salva devolve null', () async {
    expect(await store.read(), isNull);
  });

  test('grava e lê todos os campos', () async {
    await store.write(session);

    final read = await store.read();

    expect(read?.toJson(), session.toJson());
  });

  test('clear apaga a sessão', () async {
    await store.write(session);

    await store.clear();

    expect(await store.read(), isNull);
  });

  test('conteúdo que não é JSON lança FormatException', () async {
    FlutterSecureStorage.setMockInitialValues({'matrix_session': 'abc'});

    expect(store.read(), throwsFormatException);
  });

  test('campo ausente lança FormatException', () async {
    FlutterSecureStorage.setMockInitialValues({
      'matrix_session': '{"homeserver": "https://matrix.org/"}',
    });

    expect(store.read(), throwsFormatException);
  });
}
