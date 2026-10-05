import 'dart:async';

import '../../core/architecture/architecture.dart';
import '../../core/failure_mapper.dart';
import '../../src/rust/api/client.dart';
import '../../src/rust/api/room.dart';
import 'room.dart';

enum SyncStatus { syncing, connected, offline, sessionExpired }

abstract interface class RoomsRepository {
  Stream<List<Room>> watchRooms();

  Stream<SyncStatus> watchSyncStatus();

  Future<Result<void>> stopSync();
}

final class MatrixRoomsRepository implements RoomsRepository {
  MatrixRoomsRepository({required MatrixClientHandle handle})
      : _handle = handle;

  final MatrixClientHandle _handle;

  @override
  Stream<List<Room>> watchRooms() {
    return _handle
        .rooms()
        .map((rooms) => rooms.map(_toRoom).toList(growable: false))
        .transform(_failures());
  }

  @override
  Stream<SyncStatus> watchSyncStatus() {
    return _handle.syncState().map(_toSyncStatus).transform(_failures());
  }

  @override
  Future<Result<void>> stopSync() {
    return guard(_handle.stopSync, onError: mapFailure);
  }
}

StreamTransformer<T, T> _failures<T>() {
  return StreamTransformer.fromHandlers(
    handleError: (error, stackTrace, sink) =>
        sink.addError(mapFailure(error), stackTrace),
  );
}

Room _toRoom(RoomDto dto) {
  final lastActivityMs = dto.lastActivityMs?.toInt();
  final lastMessage = dto.lastMessage;
  return Room(
    id: dto.id,
    name: dto.name,
    initial: dto.initial,
    lastMessage: lastMessage == null ? null : _toLastMessage(lastMessage),
    lastActivity: lastActivityMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastActivityMs),
    unreadCount: dto.unreadCount,
    unreadMentions: dto.unreadMentions,
    isDirect: dto.isDirect,
  );
}

LastMessage _toLastMessage(LastMessageDto dto) => LastMessage(
      kind: _toMessageKind(dto.kind),
      isOwn: dto.isOwn,
      senderName: dto.senderName,
      body: dto.body,
    );

MessageKind _toMessageKind(MessageKindDto dto) => switch (dto) {
      MessageKindDto.text => MessageKind.text,
      MessageKindDto.emote => MessageKind.emote,
      MessageKindDto.notice => MessageKind.notice,
      MessageKindDto.image => MessageKind.image,
      MessageKindDto.video => MessageKind.video,
      MessageKindDto.audio => MessageKind.audio,
      MessageKindDto.file => MessageKind.file,
      MessageKindDto.location => MessageKind.location,
      MessageKindDto.sticker => MessageKind.sticker,
      MessageKindDto.encrypted => MessageKind.encrypted,
      MessageKindDto.redacted => MessageKind.redacted,
      MessageKindDto.other => MessageKind.other,
    };

SyncStatus _toSyncStatus(SyncStateDto dto) => switch (dto) {
      SyncStateDto.syncing => SyncStatus.syncing,
      SyncStateDto.connected => SyncStatus.connected,
      SyncStateDto.offline => SyncStatus.offline,
      SyncStateDto.sessionExpired => SyncStatus.sessionExpired,
    };
