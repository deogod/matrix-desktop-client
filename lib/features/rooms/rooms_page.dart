import 'package:flutter/material.dart';

import '../../core/architecture/architecture.dart';
import 'rooms_bloc.dart';
import 'rooms_stable_state.dart';

class RoomsPage extends ScreenView<RoomsBloc> {
  const RoomsPage({super.key});

  @override
  Widget build(BuildContext context, RoomsBloc bloc) {
    return Scaffold(
      body: ScreenStateBuilder(
        bloc: bloc,
        onStable: (context, data) => RoomsStableState(bloc: bloc, data: data),
        onError: (context, failure) => _buildError(context, bloc, failure),
      ),
    );
  }

  // Without a room list there is little to do here, so leaving is offered.
  Widget _buildError(BuildContext context, RoomsBloc bloc, Failure failure) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Não foi possível carregar as salas.',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(failure.message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            PersistentButton(
              bloc: bloc,
              onPressed: () => bloc.dispatchEvent(RoomsLogoutEvent()),
              child: const Text('Sair'),
            ),
          ],
        ),
      ),
    );
  }
}
