class ChatMessage {
  final String from;
  final String chatId;
  final String text;
  final DateTime timestamp;
  final String msgId;
  final List<FileMeta> files;

  ChatMessage({
    required this.from,
    this.chatId = '',
    required this.text,
    required this.timestamp,
    this.msgId = '',
    this.files = const [],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final filesList = <FileMeta>[];
    if (json['files'] != null) {
      for (final f in json['files'] as List) {
        filesList.add(FileMeta.fromJson(f as Map<String, dynamic>));
      }
    }
    return ChatMessage(
      from: json['from'] as String? ?? '',
      chatId: json['chat_id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      msgId: json['msg_id'] as String? ?? '',
      files: filesList,
    );
  }

  Map<String, dynamic> toJson() => {
    'from': from,
    'chat_id': chatId,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'msg_id': msgId,
  };
}

class MessageReplyQuote {
  final String author;
  final String preview;

  const MessageReplyQuote({required this.author, required this.preview});
}

class FormattedMessageText {
  static const _replyPrefix = '> ↩ ';
  static const _forwardPrefix = '> ↪ Forwarded from ';

  final String body;
  final MessageReplyQuote? reply;
  final String? forwardedFrom;

  const FormattedMessageText({
    required this.body,
    this.reply,
    this.forwardedFrom,
  });

  factory FormattedMessageText.parse(String text) {
    if (text.startsWith(_replyPrefix)) {
      final authorEnd = text.indexOf('\n');
      if (authorEnd > _replyPrefix.length) {
        final previewStart = authorEnd + 1;
        final bodySeparator = text.indexOf('\n\n', previewStart);
        if (bodySeparator >= previewStart &&
            text.substring(previewStart, bodySeparator).startsWith('> ')) {
          return FormattedMessageText(
            body: text.substring(bodySeparator + 2),
            reply: MessageReplyQuote(
              author: text.substring(_replyPrefix.length, authorEnd),
              preview: text.substring(previewStart + 2, bodySeparator),
            ),
          );
        }
      }
    }

    if (text.startsWith(_forwardPrefix)) {
      final authorEnd = text.indexOf('\n\n');
      if (authorEnd > _forwardPrefix.length) {
        return FormattedMessageText(
          body: text.substring(authorEnd + 2),
          forwardedFrom: text.substring(_forwardPrefix.length, authorEnd),
        );
      }
    }

    return FormattedMessageText(body: text);
  }

  static String encodeReply({
    required String author,
    required String preview,
    required String body,
  }) {
    return '$_replyPrefix${_singleLine(author)}\n> ${makePreview(preview)}\n\n$body';
  }

  static String forward({required String author, required String body}) {
    return '$_forwardPrefix${_singleLine(author)}\n\n$body';
  }

  static String makePreview(String text) {
    final parsed = FormattedMessageText.parse(text);
    final firstLine = parsed.body.split(RegExp(r'\r?\n')).first.trim();
    final normalized = firstLine.replaceAll(RegExp(r'\s+'), ' ');
    final runes = normalized.runes.toList();
    if (runes.length <= 50) return normalized;
    return '${String.fromCharCodes(runes.take(49))}…';
  }

  static String _singleLine(String value) {
    return value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  }
}

class FileMeta {
  final String fileId;
  final String filename;
  FileMeta({required this.fileId, this.filename = ''});

  factory FileMeta.fromJson(Map<String, dynamic> json) => FileMeta(
    fileId: json['file_id'] as String? ?? '',
    filename: json['filename'] as String? ?? '',
  );
}
