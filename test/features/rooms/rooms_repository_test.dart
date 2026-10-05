import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/core/architecture/architecture.dart';
import 'package:matrix_client/features/rooms/room.dart';
import 'package:matrix_client/features/rooms/rooms_repository.dart';
import 'package:matrix_client/src/rust/api/error.dart';
import 'package:matrix_client/src/rust/api/room.dart';

import '../../helpers/fake_matrix_client_handle.dart';

void main() {
  late FakeMatrixClientHandle handle;
  late MatrixRoomsRepository repository;

  setUp(() {
    handle = FakeMatrixClientHandle();
    repository = MatrixRoomsRepository(handle: handle);
  });

  test('converte as salas do Rust em entities', () async {
    final rooms = repository.watchRooms().first;
    handle.roomsController.add([
      const RoomDto(
        id: '!general:matrix.org',
        name: 'Geral',
        initial: 'G',
        lastMessage: LastMessageDto(
          senderName: 'Alice',
          isOwn: false,
          kind: MessageKindDto.image,
        ),
        lastActivityMs: 1700000000000,
        unreadCount: 3,
        unreadMentions: 1,
        isDirect: false,
      ),
      const RoomDto(
        id: '!dm:matrix.org',
        initial: '#',
        unreadCount: 0,
        unreadMentions: 0,
        isDirect: true,
      ),
    ]);

    final [general, direct] = await rooms;

    expect(general.id, '!general:matrix.org');
    expect(general.name, 'Geral');
    expect(general.initial, 'G');
    expect(general.lastMessage?.kind, MessageKind.image);
    expect(general.lastMessage?.senderName, 'Alice');
    expect(general.lastMessage?.isOwn, isFalse);
    expect(
      general.lastActivity,
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    expect(general.unreadCount, 3);
    expect(general.unreadMentions, 1);
    expect(direct.name, isNull);
    expect(direct.lastMessage, isNull);
    expect(direct.lastActivity, isNull);
    expect(direct.isDirect, isTrue);
  });

  test('converte o estado do sync', () async {
    final statuses = repository.watchSyncStatus().take(4).toList();
    for (final state in [
      SyncStateDto.syncing,
      SyncStateDto.connected,
      SyncStateDto.offline,
      SyncStateDto.sessionExpired,
    ]) {
      handle.syncStateController.add(state);
    }

    expect(await statuses, [
      SyncStatus.syncing,
      SyncStatus.connected,
      SyncStatus.offline,
      SyncStatus.sessionExpired,
    ]);
  });

  test('erros dos streams chegam como Failure', () async {
    final rooms = repository.watchRooms().first;
    handle.roomsController.addError(MatrixError.network);
    await expectLater(rooms, throwsA(isA<NetworkFailure>()));

    final statuses = repository.watchSyncStatus().first;
    handle.syncStateController.addError(Exception('falhou'));
    await expectLater(statuses, throwsA(isA<UnknownFailure>()));
  });

  test('stopSync repassa ao handle', () async {
    final result = await repository.stopSync();

    expect(result, isA<Ok<void>>());
    expect(handle.stopSyncCalls, 1);
  });
}
