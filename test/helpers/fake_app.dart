import 'package:matrix_client/core/architecture/architecture.dart';

final class FakeAppNavigator implements AppNavigator {
  final routes = <String>[];

  @override
  void offAllNamed(String route) => routes.add(route);
}

final class FakeAppHud implements AppHud {
  bool confirmResult = true;
  int confirmations = 0;
  final failures = <String>[];
  final messages = <String>[];

  @override
  void showFailure(String message) => failures.add(message);

  @override
  void showMessage(String message) => messages.add(message);

  @override
  Future<bool> confirm({
    required String title,
    required String message,
    String? confirmText,
    String? cancelText,
  }) async {
    confirmations++;
    return confirmResult;
  }
}

({FakeAppNavigator navigator, FakeAppHud hud}) registerFakeApp() {
  final navigator = FakeAppNavigator();
  final hud = FakeAppHud();
  Locator.instance
    ..reset()
    ..registerSingleton<AppNavigator>(navigator)
    ..registerSingleton<AppHud>(hud);
  return (navigator: navigator, hud: hud);
}
