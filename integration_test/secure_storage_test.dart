import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix_client/features/auth/session_store.dart';

// Checks the SecureSessionStore options against the real platform storage. It uses
// its own key so that a session saved by the app is never touched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('grava, lê e apaga com as opções do SecureSessionStore',
      (tester) async {
    const storage = SecureSessionStore.defaultStorage;
    const key = 'matrix_client_integration_test';

    await storage.write(key: key, value: 'valor');
    expect(await storage.read(key: key), 'valor');

    await storage.delete(key: key);
    expect(await storage.read(key: key), isNull);
  });
}
