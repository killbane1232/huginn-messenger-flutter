import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/src/services/messenger_service.dart';

Future<void> _serveDirectory(SendPort output) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var online = true;
  final peer = {
    'id': 'recipient-endpoint',
    'login': 'offline-recipient',
    'encryption_key': base64Encode(List.filled(32, 3)),
    'signature_key': base64Encode(List.filled(32, 4)),
    'last_seen': DateTime.now().toUtc().toIso8601String(),
    'ttl_seconds': 120,
  };
  output.send('http://127.0.0.1:${server.port}');
  await for (final request in server) {
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/health') {
      request.response.write('{"status":"ok"}');
    } else if (request.uri.path == '/test/offline') {
      online = false;
      request.response.write('{}');
    } else if (request.uri.path == '/api/v1/peers') {
      if (request.method == 'GET') {
        request.response.write(jsonEncode(online ? [peer] : []));
      } else {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.created;
      }
    } else if (request.uri.path.startsWith('/api/v1/keys/')) {
      if (online) {
        request.response.write(jsonEncode([peer]));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{"error":"peer not found"}');
      }
    } else {
      request.response.write('[]');
    }
    await request.response.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'stored offline recipient accepts text and files after restart',
    () async {
      final port = ReceivePort();
      final server = await Isolate.spawn(_serveDirectory, port.sendPort);
      final directory = await Directory.systemTemp.createTemp(
        'huginn-offline-',
      );
      var service = MessengerService();
      final client = HttpClient();
      addTearDown(() async {
        service.dispose();
        client.close(force: true);
        server.kill(priority: Isolate.immediate);
        port.close();
        await directory.delete(recursive: true);
      });
      final address = await port.first as String;
      final dbPath = '${directory.path}/huginn.db';
      expect(
        await service.init(
          username: 'sender',
          dbPath: dbPath,
          muninnAddr: address,
        ),
        isTrue,
      );
      final recipient = service.searchPeers('offline-recipient').single;
      final request = await client.postUrl(Uri.parse('$address/test/offline'));
      final response = await request.close();
      await response.drain<void>();
      service.dispose();

      service = MessengerService();
      expect(await service.init(dbPath: dbPath), isTrue);
      final restored = service.getPeers().singleWhere(
        (p) => p.key == recipient.key,
      );
      expect(restored.online, isFalse);
      expect(restored.encryptionKey, recipient.encryptionKey);
      expect(
        service.sendMessage(recipient.key, 'offline after restart'),
        isTrue,
      );
      expect(service.lastSendError, isNull);
      final attachment = File('${directory.path}/attachment.txt');
      await attachment.writeAsString('offline attachment');
      expect(
        service.sendFile(recipient.key, 'with file', attachment.path),
        isTrue,
      );
      final messages = await service.getMessages(recipient.key);
      expect(messages, hasLength(2));
      expect(messages.every((message) => !message.sendFailed), isTrue);
      expect(messages.last.files.single.filePath, attachment.path);
      service.dispose();

      service = MessengerService();
      expect(await service.init(dbPath: dbPath), isTrue);
      expect(await service.getMessages(recipient.key), hasLength(2));
      server.kill(priority: Isolate.immediate);
      expect(service.sendMessage(recipient.key, 'directory is down'), isTrue);
      final retained = await service.getMessages(recipient.key);
      expect(retained, hasLength(3));
      expect(retained.every((message) => !message.sendFailed), isTrue);
    },
    skip: Platform.environment['HUGINN_NATIVE_TESTS'] != '1',
  );
}
