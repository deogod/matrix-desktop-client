import 'dart:async';

import '../../core/architecture/architecture.dart';
import '../../core/failure_mapper.dart';
import '../../src/rust/api/client.dart';
import '../../src/rust/api/room.dart';
import '../../src/rust/api/timeline.dart';
import '../rooms/room.dart';
import 'timeline_message.dart';

abstract interface class TimelineRepository {
  Stream<List<TimelineMessage>> watchMessages(String roomId);

  Future<Result<void>> sendMessage(String roomId, String text);

  // Returns whether the start of the conversation was reached.
  Future<Result<bool>> paginateBackwards(String roomId);
}

final class MatrixTimelineRepository implements TimelineRepository {
  MatrixTimelineRepository({required MatrixClientHandle handle})
      : _handle = handle;

  final MatrixClientHandle _handle;
  final _openTimelines = <String, Future<TimelineHandle>>{};

  @override
  Stream<List<TimelineMessage>> watchMessages(String roomId) {
    late final StreamController<List<TimelineMessage>> controller;
    Future<TimelineHandle>? opening;
    StreamSubscription<List<TimelineItemDto>>? subscription;
    var cancelled = false;

    void addError(Object error, StackTrace stackTrace) {
      if (!cancelled) controller.addError(mapFailure(error), stackTrace);
    }

    controller = StreamController(
      onListen: () {
        final current = _handle.openTimeline(roomId: roomId);
        opening = current;
        _openTimelines[roomId] = current;
        current.then((timeline) {
          if (cancelled) return;
          subscription = timeline.messages().listen(
                (items) => controller.add(
                  items.map(_toMessage).toList(growable: false),
                ),
                onError: addError,
                onDone: controller.close,
              );
        }, onError: addError);
      },
      onCancel: () async {
        cancelled = true;
        await subscription?.cancel();
        final current = opening;
        if (current == null) return;
        if (identical(_openTimelines[roomId], current)) {
          _openTimelines.remove(roomId);
        }
        try {
          // Disposing the handle aborts the Rust task that feeds the stream,
          // even if the room never changes again.
          (await current).dispose();
        } catch (_) {
          // The timeline was never opened, so there is nothing to release.
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<Result<void>> sendMessage(String roomId, String text) {
    return guard(() async {
      final timeline = await _timeline(roomId);
      await timeline.sendMessage(body: text);
    }, onError: mapFailure);
  }

  @override
  Future<Result<bool>> paginateBackwards(String roomId) {
    return guard(() async {
      final timeline = await _timeline(roomId);
      return timeline.paginateBackwards();
    }, onError: mapFailure);
  }

  Future<TimelineHandle> _timeline(String roomId) {
    final timeline = _openTimelines[roomId];
    if (timeline == null) {
      throw StateError('A timeline da sala $roomId não está aberta.');
    }
    return timeline;
  }
}

TimelineMessage _toMessage(TimelineItemDto dto) => TimelineMessage(
      id: dto.id,
      senderId: dto.senderId,
      senderName: dto.senderName,
      kind: _toMessageKind(dto.kind),
      timestamp: DateTime.fromMillisecondsSinceEpoch(dto.timestampMs.toInt()),
      body: dto.body,
      undecryptableReason: switch (dto.undecryptableReason) {
        final reason? => _toUndecryptableReason(reason),
        null => null,
      },
      isOwn: dto.isOwn,
      sendStatus: _toSendStatus(dto.sendState),
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

SendStatus _toSendStatus(SendStateDto dto) => switch (dto) {
      SendStateDto.sending => SendStatus.sending,
      SendStateDto.sent => SendStatus.sent,
      SendStateDto.failed => SendStatus.failed,
    };

UndecryptableReason _toUndecryptableReason(UndecryptableReasonDto dto) =>
    switch (dto) {
      UndecryptableReasonDto.unknown => UndecryptableReason.unknown,
      UndecryptableReasonDto.sentBeforeJoined =>
        UndecryptableReason.sentBeforeJoined,
      UndecryptableReasonDto.historyUnavailable =>
        UndecryptableReason.historyUnavailable,
      UndecryptableReasonDto.unverifiedDevice =>
        UndecryptableReason.unverifiedDevice,
      UndecryptableReasonDto.withheldBySender =>
        UndecryptableReason.withheldBySender,
      UndecryptableReasonDto.untrustedSender =>
        UndecryptableReason.untrustedSender,
    };
