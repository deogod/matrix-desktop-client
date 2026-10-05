import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/core/architecture/architecture.dart';
import 'package:matrix_client/core/routes.dart';
import 'package:matrix_client/features/auth/splash/splash_bloc.dart';

import '../../helpers/fake_app.dart';
import '../../helpers/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;
  late FakeAppNavigator navigator;
  late FakeAppHud hud;
  late SplashBloc bloc;

  setUp(() {
    final app = registerFakeApp();
    navigator = app.navigator;
    hud = app.hud;
    repository = FakeAuthRepository();
    bloc = SplashBloc(authRepository: repository);
  });

  tearDown(() async {
    await bloc.close();
    Locator.instance.reset();
  });

  test('sem sessão salva vai para o login', () async {
    bloc.onReady();
    await pumpEventQueue();

    expect(navigator.routes, [Routes.login]);
    expect(hud.failures, isEmpty);
  });

  test('com sessão restaurada vai para a tela principal', () async {
    repository.restoreResult = const Ok(testSession);

    bloc.onReady();
    await pumpEventQueue();

    expect(navigator.routes, [Routes.home]);
  });

  test('falha mostra a mensagem e vai para o login', () async {
    repository.restoreResult = const Err(SessionExpiredFailure());

    bloc.onReady();
    await pumpEventQueue();

    expect(hud.failures, [const SessionExpiredFailure().message]);
    expect(navigator.routes, [Routes.login]);
  });
}
