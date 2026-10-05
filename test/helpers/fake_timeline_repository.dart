import 'dart:async';

import 'package:matrix_client/core/architecture/architecture.dart';
import 'package:matrix_client/features/rooms/room.dart';
import 'package:matrix_client/features/timeline/timeline_message.dart';
import 'package:matrix_client/features/timeline/timeline_repository.dart';

TimelineMessage testMessage(int number, {String sender = '@alice:matrix.org'}) {
  return TimelineMessage(
    id: 'item-$number',
    senderId: sender,
    senderName: sender,
    kind: MessageKind.text,
    body: 'mensagem $number',
    timestamp: DateTime(2026, 10, 5, 10, number % 60),
  );
}

final class FakeTimelineRepository implements TimelineRepository {
  final messagesController = StreamController<List<TimelineMessage>>();
  Completer<Result<bool>>? pendingPagination;
  Result<bool> paginationResult = const Ok(false);
  Result<void> sendResult = const Ok(null);

  final watchedRooms = <String>[];
  final sentMessages = <String>[];
  int paginationCalls = 0;

  @override
  Stream<List<TimelineMessage>> watchMessages(String roomId) {
    watchedRooms.add(roomId);
    return messagesController.stream;
  }

  @override
  Future<Result<void>> sendMessage(String roomId, String text) async {
    sentMessages.add(text);
    return sendResult;
  }

  @override
  Future<Result<bool>> paginateBackwards(String roomId) {
    paginationCalls++;
    return pendingPagination?.future ?? Future.value(paginationResult);
  }
}
