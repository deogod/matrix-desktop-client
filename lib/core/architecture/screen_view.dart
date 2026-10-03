import 'package:flutter/widgets.dart';

import 'bloc.dart';
import 'locator.dart';

abstract class ScreenView<B extends Bloc<dynamic, dynamic>>
    extends StatefulWidget {
  const ScreenView({super.key});

  B createBloc() => Locator.instance.get<B>();

  Widget build(BuildContext context, B bloc);

  @override
  State<ScreenView<B>> createState() => _ScreenViewState<B>();
}

class _ScreenViewState<B extends Bloc<dynamic, dynamic>>
    extends State<ScreenView<B>> {
  late final B _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = widget.createBloc()..onInit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bloc.onReady();
    });
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.build(context, _bloc);
}
