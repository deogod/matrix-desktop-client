import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/core/architecture/architecture.dart';

sealed class _Event {}

final class _LoadEvent extends _Event {}

final class _FailEvent extends _Event {}

final class _TestBloc extends Bloc<_Event, int> {
  @override
  void handleEvent(_Event event) {
    switch (event) {
      case _LoadEvent():
        dispatchState(const Stable(42));
      case _FailEvent():
        dispatchState(const ErrorState(UnknownFailure()));
    }
  }

  Future<void> persist(Future<void> Function() action) => doPersist(action);
}

void main() {
  late _TestBloc bloc;

  setUp(() => bloc = _TestBloc());

  tearDown(() async {
    if (!bloc.isClosed) await bloc.close();
  });

  test('começa em Loading', () {
    expect(bloc.state, isA<Loading<int>>());
  });

  test('publica Stable com dados tipados', () async {
    final expectation = expectLater(
      bloc.stateStream,
      emits(isA<Stable<int>>().having((s) => s.data, 'data', 42)),
    );

    bloc.dispatchEvent(_LoadEvent());

    await expectation;
    expect(bloc.state, isA<Stable<int>>());
  });

  test('publica ErrorState com a falha', () async {
    final expectation = expectLater(
      bloc.stateStream,
      emits(
        isA<ErrorState<int>>()
            .having((s) => s.failure, 'failure', isA<UnknownFailure>()),
      ),
    );

    bloc.dispatchEvent(_FailEvent());

    await expectation;
  });

  test('ignora eventos após close', () async {
    await bloc.close();

    bloc.dispatchEvent(_LoadEvent());

    expect(bloc.state, isA<Loading<int>>());
  });

  test('doPersist alterna loading → idle', () async {
    final expectation = expectLater(
      bloc.persistingStream,
      emitsInOrder([PersistingState.loading, PersistingState.idle]),
    );

    await bloc.persist(() async {});

    await expectation;
    expect(bloc.persisting, PersistingState.idle);
  });

  test('doPersist ignora chamadas concorrentes', () async {
    var calls = 0;
    Future<void> action() async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    await Future.wait([bloc.persist(action), bloc.persist(action)]);

    expect(calls, 1);
  });

  test('doPersist volta para idle mesmo se a ação lançar', () async {
    await expectLater(
      bloc.persist(() async => throw Exception('falhou')),
      throwsException,
    );

    expect(bloc.persisting, PersistingState.idle);
  });
}
