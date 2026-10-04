import 'package:flutter/material.dart';
import 'package:matrix_client/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MatrixClientApp());
}

class MatrixClientApp extends StatelessWidget {
  const MatrixClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matrix Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const _PlaceholderPage(),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Text('Matrix Client', style: theme.textTheme.headlineMedium),
      ),
    );
  }
}
