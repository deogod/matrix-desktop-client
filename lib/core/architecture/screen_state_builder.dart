import 'package:flutter/material.dart';

import 'bloc.dart';
import 'failure.dart';
import 'screen_state.dart';

class ScreenStateBuilder<Data> extends StatelessWidget {
  const ScreenStateBuilder({
    super.key,
    required this.bloc,
    required this.onStable,
    this.onLoading,
    this.onError,
  });

  final Bloc<dynamic, Data> bloc;
  final Widget Function(BuildContext context, Data data) onStable;
  final WidgetBuilder? onLoading;
  final Widget Function(BuildContext context, Failure failure)? onError;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ScreenState<Data>>(
      stream: bloc.stateStream,
      initialData: bloc.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? bloc.state;

        return switch (state) {
          Loading<Data>() => onLoading?.call(context) ??
              const Center(child: CircularProgressIndicator()),
          ErrorState<Data>(:final failure) =>
            onError?.call(context, failure) ??
                Center(child: Text(failure.message)),
          Stable<Data>(:final data) => onStable(context, data),
        };
      },
    );
  }
}
