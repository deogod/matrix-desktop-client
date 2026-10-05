import '../../../core/architecture/architecture.dart';
import '../../../core/routes.dart';
import '../auth_repository.dart';

part 'login_event.dart';

final class LoginStableData {
  const LoginStableData({this.homeserver = 'matrix.org'});

  final String homeserver;
}

final class LoginBloc extends Bloc<LoginEvent, LoginStableData> {
  LoginBloc({required this.authRepository});

  final AuthRepository authRepository;
  final LoginStableData _data = const LoginStableData();

  @override
  void onReady() {
    super.onReady();
    dispatchState(Stable(_data));
  }

  @override
  void handleEvent(LoginEvent event) {
    switch (event) {
      case LoginSubmitEvent():
        _handleSubmit(event);
    }
  }

  Future<void> _handleSubmit(LoginSubmitEvent event) => doPersist(() async {
        final result = await authRepository.login(
          homeserver: event.homeserver,
          username: event.username,
          password: event.password,
        );
        result.fold(handleFailure, (_) => offAllNamed(Routes.home));
      });
}
