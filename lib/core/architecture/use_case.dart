import 'result.dart';

abstract interface class UseCase<T, Params> {
  Future<Result<T>> call({required Params params});
}

abstract interface class StreamUseCase<T, Params> {
  Stream<T> call({required Params params});
}

final class NoParams {
  const NoParams();
}
