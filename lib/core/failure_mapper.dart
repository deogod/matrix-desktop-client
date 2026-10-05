import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../src/rust/api/error.dart';
import 'architecture/architecture.dart';

Failure mapFailure(Object error) => switch (error) {
      MatrixError.invalidCredentials => const InvalidCredentialsFailure(),
      MatrixError.invalidHomeserver => const InvalidHomeserverFailure(),
      MatrixError.network => const NetworkFailure(),
      MatrixError.sessionExpired => const SessionExpiredFailure(),
      MatrixError.storage => const StorageFailure(),
      MatrixError.unsupportedHomeserver => const InvalidHomeserverFailure(
          'Este servidor não oferece o Sliding Sync (MSC4186), necessário '
          'para este app.',
        ),
      MatrixError.unknown => const UnknownFailure(),
      PlatformException() ||
      FormatException() ||
      MissingPlatformDirectoryException() =>
        const StorageFailure(),
      _ => const UnknownFailure(),
    };
