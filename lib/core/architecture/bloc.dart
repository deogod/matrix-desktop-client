import 'dart:async';

import 'package:flutter/foundation.dart';

import 'failure.dart';
import 'hud.dart';
import 'navigation.dart';
import 'screen_state.dart';

abstract class Bloc<Event, Data> with HudMixin, NavigatorMixin {
  final _stateController = StreamController<ScreenState<Data>>.broadcast();
  final _persistingController = StreamController<PersistingState>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];

  ScreenState<Data> _state = Loading<Data>();
  PersistingState _persisting = PersistingState.idle;
  bool _isClosed = false;

  ScreenState<Data> get state => _state;

  Stream<ScreenState<Data>> get stateStream => _stateController.stream;

  PersistingState get persisting => _persisting;

  Stream<PersistingState> get persistingStream => _persistingController.stream;

  bool get isClosed => _isClosed;

  @mustCallSuper
  void onInit() {}

  @mustCallSuper
  void onReady() {}

  @protected
  void handleEvent(Event event);

  void dispatchEvent(Event event) {
    if (_isClosed) return;
    handleEvent(event);
  }

  @protected
  void dispatchState(ScreenState<Data> state) {
    if (_isClosed) return;
    _state = state;
    _stateController.add(state);
  }

  @protected
  void handleFailure(Failure failure) => showFailure(failure.message);

  @protected
  Future<void> doPersist(Future<void> Function() action) async {
    if (_persisting == PersistingState.loading) return;
    _setPersisting(PersistingState.loading);
    try {
      await action();
    } finally {
      _setPersisting(PersistingState.idle);
    }
  }

  @protected
  void addSubscription(StreamSubscription<dynamic> subscription) {
    _subscriptions.add(subscription);
  }

  @mustCallSuper
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _stateController.close();
    await _persistingController.close();
  }

  void _setPersisting(PersistingState value) {
    if (_isClosed) return;
    _persisting = value;
    _persistingController.add(value);
  }
}
