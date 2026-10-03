final class Locator {
  Locator._();

  static final Locator instance = Locator._();

  final Map<Type, _Registration<Object>> _registrations = {};

  void registerSingleton<T extends Object>(T instance) {
    _registrations[T] = _Registration<T>.instance(instance);
  }

  void registerLazySingleton<T extends Object>(T Function() create) {
    _registrations[T] = _Registration<T>.lazy(create);
  }

  void registerFactory<T extends Object>(T Function() create) {
    _registrations[T] = _Registration<T>.factory(create);
  }

  T get<T extends Object>() {
    final registration = _registrations[T];
    if (registration == null) {
      throw StateError('Dependência não registrada: $T');
    }
    return registration.resolve() as T;
  }

  void reset() => _registrations.clear();
}

final class _Registration<T extends Object> {
  _Registration.instance(T instance)
      : _create = null,
        _isFactory = false,
        _instance = instance;

  _Registration.lazy(T Function() create)
      : _create = create,
        _isFactory = false;

  _Registration.factory(T Function() create)
      : _create = create,
        _isFactory = true;

  final T Function()? _create;
  final bool _isFactory;
  T? _instance;

  T resolve() {
    if (_isFactory) return _create!();
    return _instance ??= _create!();
  }
}
