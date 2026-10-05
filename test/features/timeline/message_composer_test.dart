import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/core/architecture/architecture.dart';
import 'package:matrix_client/features/timeline/message_composer.dart';
import 'package:matrix_client/features/timeline/timeline_bloc.dart';

import '../../helpers/fake_app.dart';
import '../../helpers/fake_timeline_repository.dart';

void main() {
  late FakeTimelineRepository repository;

  setUp(() {
    registerFakeApp();
    repository = FakeTimelineRepository();
  });

  tearDown(Locator.instance.reset);

  Future<void> pumpComposer(WidgetTester tester) async {
    final bloc = TimelineBloc(
      roomId: '!room:matrix.org',
      timelineRepository: repository,
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: MessageComposer(bloc: bloc))),
    );
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('Enter envia e limpa o campo', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'oi');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(repository.sentMessages, ['oi']);
    expect(fieldText(tester), isEmpty);
  });

  testWidgets('Shift+Enter não envia', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'oi');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(repository.sentMessages, isEmpty);
    expect(fieldText(tester), startsWith('oi'));
  });

  testWidgets('mensagem vazia não é enviada', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), '   ');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(repository.sentMessages, isEmpty);
  });
}
