import 'package:flutter/material.dart';

import '../../../core/architecture/architecture.dart';
import 'login_bloc.dart';
import 'login_stable_state.dart';

class LoginPage extends ScreenView<LoginBloc> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, LoginBloc bloc) {
    return Scaffold(
      body: ScreenStateBuilder(
        bloc: bloc,
        onStable: (context, data) => LoginStableState(bloc: bloc, data: data),
      ),
    );
  }
}
