import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/core/architecture/architecture.dart';
import 'package:matrix_client/core/routes.dart';
import 'package:matrix_client/features/auth/login/login_bloc.dart';
import 'package:matrix_client/features/auth/session.dart';

import '../../helpers/fake_app.dart';
import '../../helpers/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;
  late FakeAppNavigator navigator;
  late FakeAppHud hud;
  late LoginBloc bloc;

  LoginSubmitEvent submit() => LoginSubmitEvent(
        homeserver: 'matrix.org',
        username: 'alice',
        password: 'senha',
      );

  setUp(() {
    final app = registerFakeApp();
    navigator = app.navigator;
    hud = app.hud;
    repository = FakeAuthRepository();
    bloc = LoginBloc(authRepository: repository);
  });

  tearDown(() async {
    await bloc.close();
    Locator.instance.reset();
  });

  test('publica Stable com matrix.org como servidor inicial', () {
    bloc.onReady();

    expect(
      bloc.state,
      isA<Stable<LoginStableData>>()
          .having((state) => state.data.homeserver, 'homeserver', 'matrix.org'),
    );
  });

  test('envia os dados do formulário e vai para a tela principal', () async {
    bloc.dispatchEvent(submit());
    await pumpEventQueue();

    expect(repository.loginCalls, [
      (homeserver: 'matrix.org', username: 'alice', password: 'senha'),
    ]);
    expect(navigator.routes, [Routes.home]);
    expect(hud.failures, isEmpty);
  });

  test('mostra a falha e continua no login', () async {
    repository.loginResult = const Err(InvalidCredentialsFailure());

    bloc.dispatchEvent(submit());
    await pumpEventQueue();

    expect(hud.failures, [const InvalidCredentialsFailure().message]);
    expect(navigator.routes, isEmpty);
  });

  test('fica em persistência enquanto o login não termina', () async {
    final pending = Completer<Result<Session>>();
    repository.pendingLogin = pending;

    bloc.dispatchEvent(submit());
    await pumpEventQueue();
    expect(bloc.persisting, PersistingState.loading);

    pending.complete(const Ok(testSession));
    await pumpEventQueue();
    expect(bloc.persisting, PersistingState.idle);
  });

  test('ignora novo envio enquanto o login está em andamento', () async {
    final pending = Completer<Result<Session>>();
    repository.pendingLogin = pending;

    bloc.dispatchEvent(submit());
    bloc.dispatchEvent(submit());
    pending.complete(const Ok(testSession));
    await pumpEventQueue();

    expect(repository.loginCalls, hasLength(1));
    expect(navigator.routes, [Routes.home]);
  });
}
