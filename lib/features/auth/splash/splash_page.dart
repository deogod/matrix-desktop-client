import 'package:flutter/material.dart';

import '../../../core/architecture/architecture.dart';
import 'splash_bloc.dart';

class SplashPage extends ScreenView<SplashBloc> {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, SplashBloc bloc) {
    return Scaffold(
      body: ScreenStateBuilder<void>(
        bloc: bloc,
        onLoading: _buildLoading,
        onStable: (context, _) => _buildLoading(context),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Matrix Client', style: textTheme.headlineMedium),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }
}
