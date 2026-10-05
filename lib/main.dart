import 'package:flutter/material.dart';

import 'core/architecture/architecture.dart';
import 'core/injector.dart';
import 'core/routes.dart';
import 'core/theme.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  final navigatorKey = GlobalKey<NavigatorState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  Locator.instance
    ..registerSingleton<AppNavigator>(MaterialAppNavigator(navigatorKey))
    ..registerSingleton<AppHud>(
      MaterialAppHud(navigatorKey: navigatorKey, messengerKey: messengerKey),
    );
  configureDependencies();

  runApp(
    MatrixClientApp(navigatorKey: navigatorKey, messengerKey: messengerKey),
  );
}

class MatrixClientApp extends StatelessWidget {
  const MatrixClientApp({
    super.key,
    required this.navigatorKey,
    required this.messengerKey,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matrix Client',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      initialRoute: Routes.splash,
      routes: Routes.builders,
    );
  }
}
