import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/features/rooms/room.dart';
import 'package:matrix_client/features/rooms/room_preview.dart';

Room room(LastMessage? message, {bool isDirect = false}) => Room(
      id: '!room:matrix.org',
      initial: 'S',
      lastMessage: message,
      isDirect: isDirect,
    );

LastMessage fromAlice(MessageKind kind, {String? body}) => LastMessage(
      kind: kind,
      isOwn: false,
      senderName: 'Alice',
      body: body,
    );

void main() {
  group('roomPreview', () {
    test('sem última mensagem não há prévia', () {
      expect(roomPreview(room(null)), isNull);
    });

    test('em grupo mostra quem escreveu', () {
      final message = fromAlice(MessageKind.text, body: 'oi');

      expect(roomPreview(room(message)), 'Alice: oi');
    });

    test('omite o remetente quando a sala tem o nome dele', () {
      const named = Room(
        id: '!room:matrix.org',
        name: 'Matrix.org (Official Account)',
        initial: 'M',
        lastMessage: LastMessage(
          kind: MessageKind.text,
          isOwn: false,
          senderName: 'Matrix.org (Official Account)',
          body: 'Bem-vindo',
        ),
      );

      expect(roomPreview(named), 'Bem-vindo');
    });

    test('em conversa direta omite o remetente', () {
      final message = fromAlice(MessageKind.text, body: 'oi');

      expect(roomPreview(room(message, isDirect: true)), 'oi');
    });

    test('mensagem própria começa com Você', () {
      const message = LastMessage(kind: MessageKind.text, isOwn: true, body: 'oi');

      expect(roomPreview(room(message, isDirect: true)), 'Você: oi');
    });

    test('mídia e mensagens especiais viram rótulos', () {
      final cases = {
        MessageKind.image: 'Alice: Imagem',
        MessageKind.video: 'Alice: Vídeo',
        MessageKind.audio: 'Alice: Áudio',
        MessageKind.file: 'Alice: Arquivo',
        MessageKind.location: 'Alice: Localização',
        MessageKind.sticker: 'Alice: Figurinha',
        MessageKind.encrypted: 'Alice: Mensagem criptografada',
        MessageKind.redacted: 'Alice: Mensagem apagada',
        MessageKind.other: 'Alice: Mensagem',
      };

      for (final MapEntry(key: kind, value: preview) in cases.entries) {
        expect(roomPreview(room(fromAlice(kind))), preview, reason: '$kind');
      }
    });

    test('emote é escrito na terceira pessoa', () {
      final message = fromAlice(MessageKind.emote, body: 'acena');
      const own = LastMessage(kind: MessageKind.emote, isOwn: true, body: 'acena');

      expect(roomPreview(room(message)), '* Alice acena');
      expect(roomPreview(room(own)), '* Você acena');
    });
  });

  group('activityLabel', () {
    final now = DateTime(2026, 10, 5, 15, 30);

    test('hoje mostra a hora', () {
      expect(activityLabel(DateTime(2026, 10, 5, 9, 5), now: now), '09:05');
    });

    test('ontem mostra Ontem', () {
      expect(activityLabel(DateTime(2026, 10, 4, 23, 59), now: now), 'Ontem');
    });

    test('no mesmo ano mostra dia e mês', () {
      expect(activityLabel(DateTime(2026, 3, 7, 10), now: now), '07/03');
    });

    test('em outro ano mostra a data completa', () {
      expect(activityLabel(DateTime(2025, 12, 31, 10), now: now), '31/12/25');
    });
  });
}
