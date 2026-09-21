class FileDownload {
  final String fileId;
  final String filename;
  final int receivedChunks;
  final int totalChunks;

  const FileDownload({
    required this.fileId,
    required this.filename,
    required this.receivedChunks,
    required this.totalChunks,
  });

  factory FileDownload.fromJson(Map<String, dynamic> json) => FileDownload(
    fileId: json['file_id'] as String,
    filename: json['filename'] as String? ?? '',
    receivedChunks: json['received_chunks'] as int,
    totalChunks: json['total_chunks'] as int,
  );

  double get progress =>
      totalChunks > 0 ? (receivedChunks / totalChunks).clamp(0.0, 1.0) : 0;

  String get displayName => filename.isEmpty ? fileId : filename;
}
