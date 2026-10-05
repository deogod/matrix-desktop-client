import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/core/architecture/architecture.dart';
import 'package:matrix_client/features/rooms/room.dart';
import 'package:matrix_client/features/timeline/timeline_message.dart';
import 'package:matrix_client/features/timeline/timeline_repository.dart';
import 'package:matrix_client/src/rust/api/room.dart';
import 'package:matrix_client/src/rust/api/timeline.dart';

import '../../helpers/fake_matrix_client_handle.dart';

const roomId = '!room:matrix.org';

void main() {
  late FakeMatrixClientHandle handle;
  late MatrixTimelineRepository repository;

  setUp(() {
    handle = FakeMatrixClientHandle();
    repository = MatrixTimelineRepository(handle: handle);
  });

  test('abre a timeline da sala e converte os itens', () async {
    final messages = repository.watchMessages(roomId).first;
    await pumpEventQueue();
    handle.timeline.messagesController.add([
      const TimelineItemDto(
        id: 'item-1',
        senderId: '@alice:matrix.org',
        senderName: 'Alice',
        kind: MessageKindDto.encrypted,
        undecryptableReason: UndecryptableReasonDto.unverifiedDevice,
        timestampMs: 1700000000000,
        isOwn: false,
        sendState: SendStateDto.sent,
      ),
      const TimelineItemDto(
        id: 'item-2',
        senderId: '@me:matrix.org',
        senderName: 'Eu',
        kind: MessageKindDto.text,
        body: 'oi',
        timestampMs: 1700000001000,
        isOwn: true,
        sendState: SendStateDto.failed,
      ),
    ]);

    final [received, sent] = await messages;

    expect(handle.openedTimelines, [roomId]);
    expect(received.kind, MessageKind.encrypted);
    expect(
      received.undecryptableReason,
      UndecryptableReason.unverifiedDevice,
    );
    expect(
      received.timestamp,
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    expect(sent.body, 'oi');
    expect(sent.isOwn, isTrue);
    expect(sent.sendStatus, SendStatus.failed);
  });

  test('cancelar o stream libera o handle da timeline', () async {
    final subscription = repository.watchMessages(roomId).listen((_) {});
    await pumpEventQueue();

    await subscription.cancel();

    expect(handle.timeline.isDisposed, isTrue);
  });

  test('cancelar antes de a timeline abrir também libera o handle', () async {
    final pending = Completer<TimelineHandle>();
    handle.pendingTimeline = pending;
    final subscription = repository.watchMessages(roomId).listen((_) {});
    await pumpEventQueue();

    final cancelled = subscription.cancel();
    pending.complete(handle.timeline);
    await cancelled;

    expect(handle.timeline.isDisposed, isTrue);
    expect(handle.timeline.messagesController.hasListener, isFalse);
  });

  test('envio e paginação usam a timeline aberta', () async {
    handle.timeline.reachedStart = true;
    final subscription = repository.watchMessages(roomId).listen((_) {});
    await pumpEventQueue();

    final sent = await repository.sendMessage(roomId, 'oi');
    final paginated = await repository.paginateBackwards(roomId);

    expect(sent, isA<Ok<void>>());
    expect(handle.timeline.sentBodies, ['oi']);
    expect(
      paginated,
      isA<Ok<bool>>().having((result) => result.value, 'value', isTrue),
    );
    await subscription.cancel();
  });

  test('sem timeline aberta o envio falha', () async {
    final result = await repository.sendMessage(roomId, 'oi');

    expect(
      result,
      isA<Err<void>>()
          .having((result) => result.failure, 'failure', isA<UnknownFailure>()),
    );
  });
}
