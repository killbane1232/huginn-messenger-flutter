class ChatMessage {
  final String from;
  final String text;
  final DateTime timestamp;
  final String msgId;
  final List<FileMeta> files;

  ChatMessage({
    required this.from,
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
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'msg_id': msgId,
  };
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
