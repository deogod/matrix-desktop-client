import 'package:flutter/foundation.dart';

import '../features/auth/auth_repository.dart';
import '../features/auth/login/login_bloc.dart';
import '../features/auth/session_store.dart';
import '../features/auth/splash/splash_bloc.dart';
import '../features/home/home_bloc.dart';
import '../src/rust/api/client.dart';
import 'architecture/architecture.dart';

// Must run after RustLib.init(), because the handle lives on the Rust side.
void configureDependencies() {
  final locator = Locator.instance;

  // One handle for the whole app: the session lives inside it.
  locator.registerLazySingleton<MatrixClientHandle>(
    () => MatrixClientHandle(allowInsecureLocalhost: kDebugMode),
  );
  locator.registerLazySingleton<SessionStore>(SecureSessionStore.new);
  locator.registerLazySingleton<AuthRepository>(
    () => MatrixAuthRepository(handle: locator.get(), store: locator.get()),
  );

  locator.registerFactory<SplashBloc>(
    () => SplashBloc(authRepository: locator.get()),
  );
  locator.registerFactory<LoginBloc>(
    () => LoginBloc(authRepository: locator.get()),
  );
  locator.registerFactory<HomeBloc>(
    () => HomeBloc(authRepository: locator.get()),
  );
}
