import 'dart:async';

import 'package:flutter/widgets.dart';

import 'locator.dart';

abstract interface class AppNavigator {
  void offAllNamed(String route);
}

final class MaterialAppNavigator implements AppNavigator {
  MaterialAppNavigator(this._navigatorKey);

  final GlobalKey<NavigatorState> _navigatorKey;

  @override
  void offAllNamed(String route) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      throw StateError('Navigator ainda não foi montado.');
    }
    // O Future só completa quando a rota sai da pilha.
    unawaited(navigator.pushNamedAndRemoveUntil<void>(route, (_) => false));
  }
}

mixin NavigatorMixin {
  AppNavigator get navigator => Locator.instance.get<AppNavigator>();

  void offAllNamed(String route) => navigator.offAllNamed(route);
}
