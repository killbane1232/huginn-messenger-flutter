import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/src/models/config.dart';
import 'package:huginn_messenger/src/models/muninn_ice_config.dart';
import 'package:huginn_messenger/src/services/messenger_service.dart';

// Run with HUGINN_NATIVE_TESTS=1 and LD_LIBRARY_PATH pointing to a rebuilt core.
// A separate isolate keeps HTTP responsive during synchronous native calls.
Future<void> _serveMuninn((SendPort, int) options) async {
  final (output, delay) = options;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  output.send('http://127.0.0.1:${server.port}');
  await for (final request in server) {
    if (request.uri.path == '/health') {
      await Future<void>.delayed(Duration(milliseconds: delay));
      request.response.write('{"status":"ok"}');
    } else if (request.method == 'POST' &&
        request.uri.path == '/api/v1/peers') {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      request.response.statusCode = HttpStatus.created;
      if (body.containsKey('muninn_ice') ||
          jsonEncode(body).contains('native-password')) {
        output.send('ICE credentials leaked into registration');
      }
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
    'list bootstrap selects fastest; settings and deleted chats survive restart',
    () async {
      final firstPort = ReceivePort();
      final secondPort = ReceivePort();
      final firstEvents = StreamIterator<dynamic>(firstPort);
      final secondEvents = StreamIterator<dynamic>(secondPort);
      final first = await Isolate.spawn(_serveMuninn, (firstPort.sendPort, 40));
      final second = await Isolate.spawn(_serveMuninn, (
        secondPort.sendPort,
        1,
      ));
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
      final firstICE = MuninnIceConfig(
        stunUrls: ['stun:first.example:3478'],
        turnUrls: ['turn:first.example:3478?transport=udp'],
        turnUsername: 'first-user',
        turnPassword: 'first-native-password',
      );
      final secondICE = MuninnIceConfig(
        turnUrls: ['turns:second.example:5349?transport=tcp'],
        turnUsername: 'second-user',
        turnPassword: 'second-native-password',
      );
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
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'muninn_servers': [firstAddress, secondAddress],
                'muninn_ice': {
                  firstAddress: firstICE.toJson(),
                  secondAddress: secondICE.toJson(),
                },
              }),
            ),
          ),
        );
      });

      final dbPath = '${directory.path}/huginn.db';
      expect(await service.init(username: 'alice', dbPath: dbPath), isTrue);
      expect(service.config.muninnAddr, secondAddress);
      expect(service.config.muninnServers, [firstAddress]);
      expect(
        service.config.iceFor(firstAddress).sameSettingsAs(firstICE),
        isTrue,
      );
      expect(
        service.config.iceFor(secondAddress).sameSettingsAs(secondICE),
        isTrue,
      );
      expect(await service.getFileDownloads(), isEmpty);
      await expectLater(
        service.cancelFileDownload('unknown-file'),
        throwsStateError,
      );
      await secondEvents.moveNext().timeout(const Duration(seconds: 10));
      expect(secondEvents.current, 'alice');
      // An account-only edit must preserve every candidate and its ICE credentials.
      expect(await service.setUsername('alice'), isTrue);
      expect(service.config.allMuninnServers.toSet(), {
        firstAddress,
        secondAddress,
      });

      expect(
        service.sendMessage('unknown-recipient', 'keep this message'),
        isTrue,
      );
      expect(service.lastSendError, isNull);
      final failed = (await service.getMessages('unknown-recipient')).single;
      expect(failed.sendError, 'recipient not found');
      expect(failed.text, 'keep this message');
      expect(service.retryMessage(failed.msgId), isNull);
      expect((await service.getMessages('unknown-recipient')).length, 1);
      expect(
        service.config.iceFor(secondAddress).sameSettingsAs(secondICE),
        isTrue,
      );
      final updated = AppConfig.fromJson(service.config.toJson());
      updated.muninnIce[secondAddress] = MuninnIceConfig(
        turnUrls: secondICE.turnUrls,
        turnUsername: 'changed-user',
        turnPassword: 'changed-native-password',
      );
      expect(service.saveConfig(updated), isTrue);
      await secondEvents.moveNext().timeout(const Duration(seconds: 10));
      expect(secondEvents.current, 'alice');
      expect(
        service.config.iceFor(secondAddress).turnPassword,
        'changed-native-password',
      );
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
          AppConfig(
            username: 'bob',
            muninnServers: [firstAddress],
            muninnIce: service.config.muninnIce,
          ),
        ),
        isTrue,
      );
      expect(service.config.muninnAddr, firstAddress);
      expect(service.currentUsername, 'bob');
      expect(service.config.muninnServers, isEmpty);
      expect(service.config.muninnIce.keys, [firstAddress]);
      expect(
        service.config.iceFor(firstAddress).sameSettingsAs(firstICE),
        isTrue,
      );
      await firstEvents.moveNext().timeout(const Duration(seconds: 10));
      expect(firstEvents.current, 'bob');

      service.dispose();
      service = MessengerService();
      rootBundle.evict('assets/config.json');
      messenger.setMockMessageHandler(
        'flutter/assets',
        (_) async =>
            throw StateError('Saved address must not read bootstrap config'),
      );
      expect(await service.init(dbPath: dbPath), isTrue);
      expect(service.config.muninnAddr, firstAddress);
      expect(service.config.muninnServers, isEmpty);
      expect(service.config.muninnIce.keys, [firstAddress]);
      expect(
        service.config.iceFor(firstAddress).sameSettingsAs(firstICE),
        isTrue,
      );
      await firstEvents.moveNext().timeout(const Duration(seconds: 10));
      expect(firstEvents.current, 'bob');
      expect(
        (await service.getMessages(group.uid)).single.text,
        'durably queued',
      );
      expect(service.deleteChat(''), isFalse);
      final restoredFailure = (await service.getMessages(
        'unknown-recipient',
      )).single;
      expect(restoredFailure.msgId, failed.msgId);
      expect(restoredFailure.sendFailed, isTrue);
      expect(
        service.deleteFailedMessage('unknown-recipient', failed.msgId),
        isTrue,
      );
      expect(await service.getMessages('unknown-recipient'), isEmpty);
      expect(service.deleteChat(group.uid), isTrue);
      expect(await service.getMessages(group.uid), isEmpty);
      expect(service.getHiddenChatIds(), contains(group.uid));
      service.dispose();
      service = MessengerService();
      expect(await service.init(dbPath: dbPath), isTrue);
      expect(await service.getMessages(group.uid), isEmpty);
      expect(await service.getMessages('unknown-recipient'), isEmpty);
      expect(service.getHiddenChatIds(), contains(group.uid));
      expect(service.getGroups().map((g) => g.uid), contains(group.uid));
      expect(service.sendMessage(group.uid, 'new conversation'), isTrue);
      expect(service.getHiddenChatIds(), isNot(contains(group.uid)));
      expect(
        (await service.getMessages(group.uid)).single.text,
        'new conversation',
      );
    },
    skip: Platform.environment['HUGINN_NATIVE_TESTS'] != '1',
  );
}
