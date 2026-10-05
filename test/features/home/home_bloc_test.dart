import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/core/architecture/architecture.dart';
import 'package:matrix_client/core/routes.dart';
import 'package:matrix_client/features/auth/auth_repository.dart';
import 'package:matrix_client/features/home/home_bloc.dart';

import '../../helpers/fake_app.dart';
import '../../helpers/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;
  late FakeAppNavigator navigator;
  late FakeAppHud hud;
  late HomeBloc bloc;

  setUp(() {
    final app = registerFakeApp();
    navigator = app.navigator;
    hud = app.hud;
    repository = FakeAuthRepository();
    bloc = HomeBloc(authRepository: repository);
  });

  tearDown(() async {
    await bloc.close();
    Locator.instance.reset();
  });

  Future<void> logout() async {
    bloc.dispatchEvent(HomeLogoutEvent());
    await pumpEventQueue();
  }

  test('pede confirmação e não sai se for cancelado', () async {
    hud.confirmResult = false;

    await logout();

    expect(hud.confirmations, 1);
    expect(repository.logoutCalls, 0);
    expect(navigator.routes, isEmpty);
  });

  test('logout completo vai para o login sem aviso', () async {
    await logout();

    expect(repository.logoutCalls, 1);
    expect(hud.messages, isEmpty);
    expect(navigator.routes, [Routes.login]);
  });

  test('logout só local avisa que o servidor não foi avisado', () async {
    repository.logoutResult = const Ok(LogoutOutcome.localOnly);

    await logout();

    expect(hud.messages, [HomeBloc.localOnlyLogoutMessage]);
    expect(navigator.routes, [Routes.login]);
  });

  test('falha no logout mostra a falha e vai para o login', () async {
    repository.logoutResult = const Err(StorageFailure());

    await logout();

    expect(hud.failures, [const StorageFailure().message]);
    expect(navigator.routes, [Routes.login]);
  });
}
