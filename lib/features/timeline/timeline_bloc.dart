import '../../core/architecture/architecture.dart';
import 'timeline_message.dart';
import 'timeline_repository.dart';

part 'timeline_event.dart';

final class TimelineStableData {
  const TimelineStableData({
    this.messages = const [],
    this.isLoadingOlder = false,
    this.reachedStart = false,
  });

  // Oldest first.
  final List<TimelineMessage> messages;
  final bool isLoadingOlder;
  final bool reachedStart;

  bool get isEmpty => messages.isEmpty;

  TimelineStableData copyWith({
    List<TimelineMessage>? messages,
    bool? isLoadingOlder,
    bool? reachedStart,
  }) {
    return TimelineStableData(
      messages: messages ?? this.messages,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      reachedStart: reachedStart ?? this.reachedStart,
    );
  }
}

final class TimelineBloc extends Bloc<TimelineEvent, TimelineStableData> {
  TimelineBloc({required this.roomId, required this.timelineRepository});

  static const _firstPageSize = 20;

  final String roomId;
  final TimelineRepository timelineRepository;
  TimelineStableData _data = const TimelineStableData();
  bool _hasReceivedMessages = false;

  @override
  void onReady() {
    super.onReady();
    dispatchEvent(TimelineStartEvent());
  }

  @override
  void handleEvent(TimelineEvent event) {
    switch (event) {
      case TimelineStartEvent():
        _handleStart();
      case TimelineLoadOlderEvent():
        _handleLoadOlder();
      case TimelineSendEvent():
        _handleSend(event.text);
    }
  }

  void _handleStart() {
    addSubscription(
      timelineRepository
          .watchMessages(roomId)
          .listen(_onMessages, onError: _onMessagesError),
    );
  }

  void _onMessages(List<TimelineMessage> messages) {
    final isFirstList = !_hasReceivedMessages;
    _hasReceivedMessages = true;
    _data = _data.copyWith(messages: messages);
    dispatchState(Stable(_data));

    // A short first page does not fill the panel, so no scroll would ask for
    // older messages.
    if (isFirstList && messages.length < _firstPageSize) _handleLoadOlder();
  }

  void _onMessagesError(Object error) {
    final failure = error is Failure ? error : const UnknownFailure();
    if (_hasReceivedMessages) {
      handleFailure(failure);
    } else {
      dispatchState(ErrorState(failure));
    }
  }

  Future<void> _handleLoadOlder() async {
    if (!_hasReceivedMessages || _data.isLoadingOlder || _data.reachedStart) {
      return;
    }
    _data = _data.copyWith(isLoadingOlder: true);
    dispatchState(Stable(_data));

    final result = await timelineRepository.paginateBackwards(roomId);
    result.fold(handleFailure, (reachedStart) {
      _data = _data.copyWith(reachedStart: reachedStart);
    });
    _data = _data.copyWith(isLoadingOlder: false);
    dispatchState(Stable(_data));
  }

  Future<void> _handleSend(String text) async {
    final body = text.trim();
    if (body.isEmpty) return;

    await doPersist(() async {
      final result = await timelineRepository.sendMessage(roomId, body);
      result.fold(handleFailure, (_) {});
    });
  }
}
