part of 'login_bloc.dart';

sealed class LoginEvent {}

final class LoginSubmitEvent extends LoginEvent {
  LoginSubmitEvent({
    required this.homeserver,
    required this.username,
    required this.password,
  });

  final String homeserver;
  final String username;
  final String password;
}
