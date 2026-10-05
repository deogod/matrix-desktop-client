import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'core/architecture/architecture.dart';
import 'core/injector.dart';
import 'core/routes.dart';
import 'core/theme.dart';
import 'features/rooms/rooms_repository.dart';
import 'src/rust/frb_generated.dart';

const _stopSyncTimeout = Duration(seconds: 2);

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
    MatrixClientApp(
      navigatorKey: navigatorKey,
      messengerKey: messengerKey,
      beforeExit: _stopSync,
    ),
  );
}

Future<void> _stopSync() async {
  try {
    await Locator.instance
        .get<RoomsRepository>()
        .stopSync()
        .timeout(_stopSyncTimeout);
  } on TimeoutException {
    // Without network the sync can take a while to stop; the app closes anyway.
  }
}

class MatrixClientApp extends StatefulWidget {
  const MatrixClientApp({
    super.key,
    required this.navigatorKey,
    required this.messengerKey,
    required this.beforeExit,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final Future<void> Function() beforeExit;

  @override
  State<MatrixClientApp> createState() => _MatrixClientAppState();
}

class _MatrixClientAppState extends State<MatrixClientApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener =
        AppLifecycleListener(onExitRequested: _onExitRequested);
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  Future<AppExitResponse> _onExitRequested() async {
    await widget.beforeExit();
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matrix Client',
      debugShowCheckedModeBanner: false,
      navigatorKey: widget.navigatorKey,
      scaffoldMessengerKey: widget.messengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      initialRoute: Routes.splash,
      routes: Routes.builders,
    );
  }
}
