import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/core/architecture/architecture.dart';
import 'package:matrix_client/features/auth/login/login_bloc.dart';
import 'package:matrix_client/features/auth/login/login_stable_state.dart';
import 'package:matrix_client/features/auth/session.dart';

import '../../helpers/fake_app.dart';
import '../../helpers/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;

  setUp(() {
    registerFakeApp();
    repository = FakeAuthRepository();
  });

  tearDown(Locator.instance.reset);

  Future<void> pumpForm(WidgetTester tester) async {
    final bloc = LoginBloc(authRepository: repository);
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginStableState(bloc: bloc, data: const LoginStableData()),
        ),
      ),
    );
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  final submitButton = find.widgetWithText(FilledButton, 'Entrar');

  Future<void> fillForm(WidgetTester tester) async {
    await tester.enterText(field('Servidor'), '  matrix.org  ');
    await tester.enterText(field('Usuário'), ' alice ');
    await tester.enterText(field('Senha'), ' senha ');
  }

  testWidgets('servidor vem preenchido com matrix.org', (tester) async {
    await pumpForm(tester);

    final homeserver = tester.widget<TextFormField>(field('Servidor'));
    expect(homeserver.controller?.text, 'matrix.org');
  });

  testWidgets('campos vazios mostram erros e não enviam', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('Servidor'), '   ');

    await tester.tap(submitButton);
    await tester.pump();

    expect(find.text('Informe o servidor.'), findsOneWidget);
    expect(find.text('Informe o usuário.'), findsOneWidget);
    expect(find.text('Informe a senha.'), findsOneWidget);
    expect(repository.loginCalls, isEmpty);
  });

  testWidgets('Enter na senha envia uma vez, sem espaços em servidor e usuário',
      (tester) async {
    await pumpForm(tester);
    await fillForm(tester);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(repository.loginCalls, [
      (homeserver: 'matrix.org', username: 'alice', password: ' senha '),
    ]);
  });

  testWidgets('botão Entrar envia o formulário', (tester) async {
    await pumpForm(tester);
    await fillForm(tester);

    await tester.tap(submitButton);
    await tester.pump();

    expect(repository.loginCalls, hasLength(1));
  });

  testWidgets('não reenvia enquanto o login está em andamento', (tester) async {
    final pending = Completer<Result<Session>>();
    repository.pendingLogin = pending;
    await pumpForm(tester);
    await fillForm(tester);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(repository.loginCalls, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(const Ok(testSession));
    await tester.pump();
  });
}
