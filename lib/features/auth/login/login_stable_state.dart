import 'package:flutter/material.dart';

import '../../../core/architecture/architecture.dart';
import 'login_bloc.dart';

class LoginStableState extends StatefulWidget {
  const LoginStableState({super.key, required this.bloc, required this.data});

  final LoginBloc bloc;
  final LoginStableData data;

  @override
  State<LoginStableState> createState() => _LoginStableStateState();
}

class _LoginStableStateState extends State<LoginStableState> {
  final _formKey = GlobalKey<FormState>();
  late final _homeserverController =
      TextEditingController(text: widget.data.homeserver);
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _homeserverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    widget.bloc.dispatchEvent(
      LoginSubmitEvent(
        homeserver: _homeserverController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Entrar', style: textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text('Use sua conta Matrix.', style: textTheme.bodyMedium),
                  const SizedBox(height: 32),
                  _buildHomeserverField(),
                  const SizedBox(height: 16),
                  _buildUsernameField(),
                  const SizedBox(height: 16),
                  _buildPasswordField(),
                  const SizedBox(height: 24),
                  PersistentButton(
                    bloc: widget.bloc,
                    onPressed: _submit,
                    child: const Text('Entrar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeserverField() {
    return TextFormField(
      controller: _homeserverController,
      decoration: const InputDecoration(
        labelText: 'Servidor',
        helperText: 'Ex.: matrix.org ou https://matrix.exemplo.com',
      ),
      keyboardType: TextInputType.url,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      validator: (value) => _requiredText(value, 'Informe o servidor.'),
    );
  }

  Widget _buildUsernameField() {
    return TextFormField(
      controller: _usernameController,
      decoration: const InputDecoration(
        labelText: 'Usuário',
        helperText: 'Ex.: alice ou @alice:matrix.org',
      ),
      autocorrect: false,
      autofillHints: const [AutofillHints.username],
      textInputAction: TextInputAction.next,
      validator: (value) => _requiredText(value, 'Informe o usuário.'),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      decoration: InputDecoration(
        labelText: 'Senha',
        suffixIcon: IconButton(
          tooltip: _obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
          icon: Icon(
            _obscurePassword ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      obscureText: _obscurePassword,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [AutofillHints.password],
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _submit(),
      validator: (value) =>
          value == null || value.isEmpty ? 'Informe a senha.' : null,
    );
  }

  static String? _requiredText(String? value, String message) {
    return value == null || value.trim().isEmpty ? message : null;
  }
}
