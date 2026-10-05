import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/architecture/architecture.dart';
import 'timeline_bloc.dart';

class MessageComposer extends StatefulWidget {
  const MessageComposer({super.key, required this.bloc});

  final TimelineBloc bloc;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();
  late final _focusNode = FocusNode(onKeyEvent: _onKeyEvent);

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (event is! KeyDownEvent || !isEnter) return KeyEventResult.ignored;
    // Shift+Enter reaches the text field, which inserts the line break.
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    // While an input method is composing, Enter confirms the composition.
    if (_controller.value.composing.isValid) return KeyEventResult.ignored;

    _send();
    return KeyEventResult.handled;
  }

  void _send() {
    if (_controller.text.trim().isEmpty) return;
    // A send still in progress would make the bloc drop this one, so the text
    // stays in the field instead of being lost.
    if (widget.bloc.persisting == PersistingState.loading) return;

    widget.bloc.dispatchEvent(TimelineSendEvent(_controller.text));
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              minLines: 1,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Escreva uma mensagem',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          PersistentButton(
            bloc: widget.bloc,
            onPressed: _send,
            child: const Icon(Icons.send, size: 18, semanticLabel: 'Enviar'),
          ),
        ],
      ),
    );
  }
}
