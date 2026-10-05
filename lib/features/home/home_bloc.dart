import '../../core/architecture/architecture.dart';
import '../../core/routes.dart';
import '../auth/auth_repository.dart';

sealed class HomeEvent {}

final class HomeLogoutEvent extends HomeEvent {}

final class HomeStableData {
  const HomeStableData();
}

final class HomeBloc extends Bloc<HomeEvent, HomeStableData> {
  HomeBloc({required this.authRepository});

  static const localOnlyLogoutMessage =
      'Sessão encerrada neste computador, mas não foi possível avisar o '
      'servidor. O acesso pode continuar ativo até ser revogado em outro '
      'dispositivo.';

  final AuthRepository authRepository;
  final HomeStableData _data = const HomeStableData();

  @override
  void onReady() {
    super.onReady();
    dispatchState(Stable(_data));
  }

  @override
  void handleEvent(HomeEvent event) {
    switch (event) {
      case HomeLogoutEvent():
        _handleLogout();
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showConfirmation(
      title: 'Sair da conta',
      message: 'A sessão será encerrada e os dados desta conta serão apagados '
          'deste computador.',
      confirmText: 'Sair',
    );
    if (!confirmed) return;

    await doPersist(() async {
      final result = await authRepository.logout();
      // Local data is gone even when logout fails, so the user always leaves.
      result.fold(handleFailure, (outcome) {
        if (outcome == LogoutOutcome.localOnly) {
          showMessage(localOnlyLogoutMessage);
        }
      });
      offAllNamed(Routes.login);
    });
  }
}
