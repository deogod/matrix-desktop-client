import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/core/architecture/architecture.dart';
import 'package:matrix_client/features/timeline/timeline_bloc.dart';
import 'package:matrix_client/features/timeline/timeline_message.dart';

import '../../helpers/fake_app.dart';
import '../../helpers/fake_timeline_repository.dart';

const roomId = '!room:matrix.org';

List<TimelineMessage> page(int count) =>
    [for (var number = 0; number < count; number++) testMessage(number)];

void main() {
  late FakeTimelineRepository repository;
  late FakeAppHud hud;
  late TimelineBloc bloc;

  setUp(() {
    hud = registerFakeApp().hud;
    repository = FakeTimelineRepository();
    bloc = TimelineBloc(roomId: roomId, timelineRepository: repository)
      ..onReady();
  });

  tearDown(() async {
    await bloc.close();
    Locator.instance.reset();
  });

  TimelineStableData stableData() {
    final state = bloc.state;
    if (state is! Stable<TimelineStableData>) {
      fail('Esperava Stable, veio $state');
    }
    return state.data;
  }

  Future<void> emitMessages(List<TimelineMessage> messages) async {
    repository.messagesController.add(messages);
    await pumpEventQueue();
  }

  group('mensagens', () {
    test('assina a timeline da sala e espera a primeira lista', () async {
      await pumpEventQueue();

      expect(repository.watchedRooms, [roomId]);
      expect(bloc.state, isA<Loading<TimelineStableData>>());
    });

    test('publica as mensagens recebidas', () async {
      final messages = page(20);

      await emitMessages(messages);

      expect(stableData().messages, messages);
      expect(repository.paginationCalls, 0);
    });

    test('falha antes da primeira lista vira ErrorState', () async {
      repository.messagesController.addError(const NetworkFailure());
      await pumpEventQueue();

      expect(bloc.state, isA<ErrorState<TimelineStableData>>());
    });

    test('falha depois da primeira lista mantém as mensagens e avisa',
        () async {
      await emitMessages(page(20));

      repository.messagesController.addError(const NetworkFailure());
      await pumpEventQueue();

      expect(stableData().messages, hasLength(20));
      expect(hud.failures, [const NetworkFailure().message]);
    });
  });

  group('paginação', () {
    test('pede mensagens antigas quando a primeira página é curta', () async {
      await emitMessages(page(3));

      expect(repository.paginationCalls, 1);
    });

    test('não pagina de novo enquanto uma paginação está em andamento',
        () async {
      final pending = Completer<Result<bool>>();
      repository.pendingPagination = pending;
      await emitMessages(page(20));

      bloc.dispatchEvent(TimelineLoadOlderEvent());
      bloc.dispatchEvent(TimelineLoadOlderEvent());
      await pumpEventQueue();

      expect(repository.paginationCalls, 1);
      expect(stableData().isLoadingOlder, isTrue);

      pending.complete(const Ok(false));
      await pumpEventQueue();
      expect(stableData().isLoadingOlder, isFalse);
    });

    test('para de paginar ao chegar ao início da conversa', () async {
      repository.paginationResult = const Ok(true);
      await emitMessages(page(3));

      bloc.dispatchEvent(TimelineLoadOlderEvent());
      await pumpEventQueue();

      expect(stableData().reachedStart, isTrue);
      expect(repository.paginationCalls, 1);
    });

    test('falha avisa pela HUD e permite tentar de novo', () async {
      repository.paginationResult = const Err(NetworkFailure());
      await emitMessages(page(20));

      bloc.dispatchEvent(TimelineLoadOlderEvent());
      await pumpEventQueue();

      expect(hud.failures, [const NetworkFailure().message]);
      expect(stableData().isLoadingOlder, isFalse);
      expect(stableData().reachedStart, isFalse);

      bloc.dispatchEvent(TimelineLoadOlderEvent());
      await pumpEventQueue();
      expect(repository.paginationCalls, 2);
    });
  });

  group('envio', () {
    test('envia o texto sem espaços nas pontas', () async {
      bloc.dispatchEvent(TimelineSendEvent('  oi\ntudo bem?  \n'));
      await pumpEventQueue();

      expect(repository.sentMessages, ['oi\ntudo bem?']);
    });

    test('ignora mensagem vazia', () async {
      bloc.dispatchEvent(TimelineSendEvent('   \n  '));
      await pumpEventQueue();

      expect(repository.sentMessages, isEmpty);
    });

    test('falha no envio avisa pela HUD', () async {
      repository.sendResult = const Err(UnknownFailure());

      bloc.dispatchEvent(TimelineSendEvent('oi'));
      await pumpEventQueue();

      expect(hud.failures, [const UnknownFailure().message]);
    });
  });
}
