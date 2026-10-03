import 'dart:developer';

import 'failure.dart';

sealed class Result<T> {
  const Result();

  R fold<R>(
    R Function(Failure failure) onFailure,
    R Function(T value) onSuccess,
  ) {
    return switch (this) {
      Ok<T>(:final value) => onSuccess(value),
      Err<T>(:final failure) => onFailure(failure),
    };
  }
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;
}

Future<Result<T>> guard<T>(
  Future<T> Function() body, {
  required Failure Function(Object error) onError,
}) async {
  try {
    return Ok(await body());
  } catch (error, stackTrace) {
    log('guard: $error', error: error, stackTrace: stackTrace);
    return Err(onError(error));
  }
}
