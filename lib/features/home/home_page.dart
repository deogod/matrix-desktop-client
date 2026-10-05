import 'package:flutter/material.dart';

import '../../core/architecture/architecture.dart';
import 'home_bloc.dart';

class HomePage extends ScreenView<HomeBloc> {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, HomeBloc bloc) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matrix Client')),
      body: ScreenStateBuilder(
        bloc: bloc,
        onStable: (context, data) => _buildBody(context, bloc),
      ),
    );
  }

  Widget _buildBody(BuildContext context, HomeBloc bloc) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Você está conectado.', style: textTheme.titleMedium),
          const SizedBox(height: 24),
          PersistentButton(
            bloc: bloc,
            onPressed: () => bloc.dispatchEvent(HomeLogoutEvent()),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
  }
}
