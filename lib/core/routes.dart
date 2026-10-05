import 'package:flutter/widgets.dart';

import '../features/auth/login/login_page.dart';
import '../features/auth/splash/splash_page.dart';
import '../features/home/home_page.dart';

abstract final class Routes {
  static const splash = '/';
  static const login = '/login';
  static const home = '/home';

  static final Map<String, WidgetBuilder> builders = {
    splash: (_) => const SplashPage(),
    login: (_) => const LoginPage(),
    home: (_) => const HomePage(),
  };
}
