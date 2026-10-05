import 'dart:async';

import 'package:matrix_client/core/architecture/architecture.dart';
import 'package:matrix_client/features/rooms/room.dart';
import 'package:matrix_client/features/rooms/rooms_repository.dart';

final class FakeRoomsRepository implements RoomsRepository {
  final roomsController = StreamController<List<Room>>();
  final syncStatusController = StreamController<SyncStatus>();
  int stopSyncCalls = 0;

  @override
  Stream<List<Room>> watchRooms() => roomsController.stream;

  @override
  Stream<SyncStatus> watchSyncStatus() => syncStatusController.stream;

  @override
  Future<Result<void>> stopSync() async {
    stopSyncCalls++;
    return const Ok(null);
  }
}
