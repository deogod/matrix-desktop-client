sealed class Failure {
  const Failure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

final class NetworkFailure extends Failure {
  const NetworkFailure([
    super.message = 'Não foi possível conectar ao servidor.',
  ]);
}

final class InvalidHomeserverFailure extends Failure {
  const InvalidHomeserverFailure([
    super.message = 'Servidor Matrix inválido ou inacessível.',
  ]);
}

final class InvalidCredentialsFailure extends Failure {
  const InvalidCredentialsFailure([
    super.message = 'Usuário ou senha inválidos.',
  ]);
}

final class SessionExpiredFailure extends Failure {
  const SessionExpiredFailure([
    super.message = 'Sua sessão expirou. Entre novamente.',
  ]);
}

final class StorageFailure extends Failure {
  const StorageFailure([
    super.message = 'Não foi possível acessar os dados locais.',
  ]);
}

final class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Ocorreu um erro inesperado.']);
}
