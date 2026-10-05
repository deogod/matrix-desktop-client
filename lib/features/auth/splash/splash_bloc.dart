import '../../../core/architecture/architecture.dart';
import '../../../core/routes.dart';
import '../auth_repository.dart';

sealed class SplashEvent {}

final class SplashRestoreEvent extends SplashEvent {}

// The splash only decides where to go, so it never leaves the Loading state.
final class SplashBloc extends Bloc<SplashEvent, void> {
  SplashBloc({required this.authRepository});

  final AuthRepository authRepository;

  @override
  void onReady() {
    super.onReady();
    dispatchEvent(SplashRestoreEvent());
  }

  @override
  void handleEvent(SplashEvent event) {
    switch (event) {
      case SplashRestoreEvent():
        _handleRestore();
    }
  }

  Future<void> _handleRestore() async {
    final result = await authRepository.restoreSession();
    result.fold(
      (failure) {
        handleFailure(failure);
        offAllNamed(Routes.login);
      },
      (session) => offAllNamed(session == null ? Routes.login : Routes.home),
    );
  }
}
