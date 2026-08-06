import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/src/models/chat_message.dart';

void main() {
  test('reply is encoded in text and parsed back', () {
    final encoded = FormattedMessageText.encodeReply(
      author: 'Alice',
      preview: 'First line\nSecond line',
      body: 'My answer',
    );

    expect(encoded, '> ↩ Alice\n> First line\n\nMy answer');
    final parsed = FormattedMessageText.parse(encoded);
    expect(parsed.reply?.author, 'Alice');
    expect(parsed.reply?.preview, 'First line');
    expect(parsed.body, 'My answer');
  });

  test('reply preview is limited to 50 Unicode characters', () {
    final preview = FormattedMessageText.makePreview('😀' * 60);

    expect(preview.runes.length, 50);
    expect(preview.endsWith('…'), isTrue);
  });

  test('forward is encoded in text and parsed back', () {
    final encoded = FormattedMessageText.forward(
      author: 'Bob',
      body: 'Forwarded body',
    );

    expect(encoded, '> ↪ Forwarded from Bob\n\nForwarded body');
    final parsed = FormattedMessageText.parse(encoded);
    expect(parsed.forwardedFrom, 'Bob');
    expect(parsed.body, 'Forwarded body');
  });
}
