import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/src/models/config.dart';
import 'package:huginn_messenger/src/services/messenger_service.dart';

// Run with HUGINN_NATIVE_TESTS=1 and LD_LIBRARY_PATH pointing to a rebuilt core.
// A separate isolate keeps HTTP responsive during synchronous native calls.
Future<void> _serveMuninn(SendPort output) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  output.send('http://127.0.0.1:${server.port}');
  await for (final request in server) {
    if (request.method == 'POST' && request.uri.path == '/api/v1/peers') {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      request.response.statusCode = HttpStatus.created;
      if (body['fake'] != true) output.send(body['login']);
    } else {
      request.response.headers.contentType = ContentType.json;
      request.response.write('[]');
    }
    await request.response.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'asset bootstrap, immediate address change and SQLite restart',
    () async {
      final firstPort = ReceivePort();
      final secondPort = ReceivePort();
      final firstEvents = StreamIterator<dynamic>(firstPort);
      final secondEvents = StreamIterator<dynamic>(secondPort);
      final first = await Isolate.spawn(_serveMuninn, firstPort.sendPort);
      final second = await Isolate.spawn(_serveMuninn, secondPort.sendPort);
      final directory = await Directory.systemTemp.createTemp('huginn-config-');
      var service = MessengerService();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() async {
        service.dispose();
        messenger.setMockMessageHandler('flutter/assets', null);
        rootBundle.evict('assets/config.json');
        first.kill(priority: Isolate.immediate);
        second.kill(priority: Isolate.immediate);
        await firstEvents.cancel();
        await secondEvents.cancel();
        firstPort.close();
        secondPort.close();
        await directory.delete(recursive: true);
      });
      await firstEvents.moveNext();
      final firstAddress = firstEvents.current as String;
      await secondEvents.moveNext();
      final secondAddress = secondEvents.current as String;
      rootBundle.evict('assets/config.json');
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        if (key != 'assets/config.json') return null;
        return ByteData.sublistView(
          Uint8List.fromList(utf8.encode(jsonEncode({'muninn': firstAddress}))),
        );
      });

      final dbPath = '${directory.path}/huginn.db';
      expect(await service.init(username: 'alice', dbPath: dbPath), isTrue);
      expect(service.config.muninnAddr, firstAddress);
      await firstEvents.moveNext().timeout(const Duration(seconds: 10));
      expect(firstEvents.current, 'alice');

      expect(
        service.sendMessage('unknown-recipient', 'keep this draft'),
        isFalse,
      );
      expect(service.lastSendError, 'recipient not found');
      final group = await service.createGroup('delivery regression');
      expect(group, isNotNull);
      expect(
        service.sendFile(
          group!.uid,
          'attachment',
          '${directory.path}/missing.txt',
        ),
        isFalse,
      );
      expect(service.lastSendError, 'cannot read attachment');
      expect(await service.getMessages(group.uid), isEmpty);
      expect(service.sendMessage(group.uid, 'durably queued'), isTrue);
      expect(service.lastSendError, isNull);
      expect(
        (await service.getMessages(group.uid)).single.text,
        'durably queued',
      );

      expect(
        service.saveConfig(
          AppConfig(username: 'bob', muninnAddr: secondAddress),
        ),
        isTrue,
      );
      expect(service.config.muninnAddr, secondAddress);
      expect(service.currentUsername, 'bob');
      await secondEvents.moveNext().timeout(const Duration(seconds: 10));
      expect(secondEvents.current, 'bob');

      service.dispose();
      service = MessengerService();
      rootBundle.evict('assets/config.json');
      messenger.setMockMessageHandler(
        'flutter/assets',
        (_) async =>
            throw StateError('Saved address must not read bootstrap config'),
      );
      expect(await service.init(dbPath: dbPath), isTrue);
      expect(service.config.muninnAddr, secondAddress);
      await secondEvents.moveNext().timeout(const Duration(seconds: 10));
      expect(secondEvents.current, 'bob');
      expect(
        (await service.getMessages(group.uid)).single.text,
        'durably queued',
      );
    },
    skip: Platform.environment['HUGINN_NATIVE_TESTS'] != '1',
  );
}
