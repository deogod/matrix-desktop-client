import 'package:flutter/material.dart';

import 'locator.dart';

abstract interface class AppHud {
  void showFailure(String message);

  Future<bool> confirm({
    required String title,
    required String message,
    String? confirmText,
    String? cancelText,
  });
}

final class MaterialAppHud implements AppHud {
  MaterialAppHud({
    required GlobalKey<NavigatorState> navigatorKey,
    required GlobalKey<ScaffoldMessengerState> messengerKey,
  })  : _navigatorKey = navigatorKey,
        _messengerKey = messengerKey;

  final GlobalKey<NavigatorState> _navigatorKey;
  final GlobalKey<ScaffoldMessengerState> _messengerKey;

  @override
  void showFailure(String message) {
    final messenger = _messengerKey.currentState;
    // O ScaffoldMessenger fica acima do Theme no MaterialApp.
    final themeContext = _navigatorKey.currentContext;
    if (messenger == null || themeContext == null) return;

    final colors = Theme.of(themeContext).colorScheme;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.error,
          content: Text(message, style: TextStyle(color: colors.onError)),
        ),
      );
  }

  @override
  Future<bool> confirm({
    required String title,
    required String message,
    String? confirmText,
    String? cancelText,
  }) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelText ?? 'Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmText ?? 'Confirmar'),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }
}

mixin HudMixin {
  AppHud get hud => Locator.instance.get<AppHud>();

  void showFailure(String message) => hud.showFailure(message);

  Future<bool> showConfirmation({
    required String title,
    required String message,
    String? confirmText,
    String? cancelText,
  }) {
    return hud.confirm(
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
    );
  }
}
