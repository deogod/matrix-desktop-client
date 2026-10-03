import 'failure.dart';

sealed class ScreenState<Data> {
  const ScreenState();
}

final class Loading<Data> extends ScreenState<Data> {
  const Loading();
}

final class Stable<Data> extends ScreenState<Data> {
  const Stable(this.data);

  final Data data;
}

final class ErrorState<Data> extends ScreenState<Data> {
  const ErrorState(this.failure);

  final Failure failure;
}

enum PersistingState { idle, loading }
