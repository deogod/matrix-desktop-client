import 'package:flutter/material.dart';

import 'bloc.dart';
import 'screen_state.dart';

class PersistentButton extends StatelessWidget {
  const PersistentButton({
    super.key,
    required this.bloc,
    required this.onPressed,
    required this.child,
  });

  final Bloc<dynamic, dynamic> bloc;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PersistingState>(
      stream: bloc.persistingStream,
      initialData: bloc.persisting,
      builder: (context, snapshot) {
        final isLoading = snapshot.data == PersistingState.loading;

        return FilledButton(
          onPressed: isLoading ? null : onPressed,
          child: isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : child,
        );
      },
    );
  }
}
