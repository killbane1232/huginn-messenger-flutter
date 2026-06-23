import 'peer.dart';
import 'chat_message.dart';

sealed class AppEvent {
  final String type;
  AppEvent(this.type);
}

class PeersEvent extends AppEvent {
  final List<Peer> peers;
  PeersEvent(this.peers) : super('peers');
}

class MessageEvent extends AppEvent {
  final ChatMessage message;
  MessageEvent(this.message) : super('message');
}

class FileReadyEvent extends AppEvent {
  final String fileId;
  final String filePath;
  final String filename;
  final String senderId;
  FileReadyEvent({
    required this.fileId,
    required this.filePath,
    required this.filename,
    required this.senderId,
  }) : super('file_ready');
}
