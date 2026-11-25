import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/huginn_messenger.dart';

// Keep the test server responsive during synchronous FFI calls.
Future<void> _serve(SendPort output) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final commands = ReceivePort();
  final sockets = <WebSocket>{};
  var allowConnection = false;
  commands.listen((command) {
    allowConnection = command == 'connect';
    if (!allowConnection) {
      for (final socket in sockets.toList()) {
        unawaited(socket.close());
      }
    }
    output.send(command);
  });
  output.send(['http://127.0.0.1:${server.port}', commands.sendPort]);
  await for (final request in server) {
    if (request.uri.path == '/api/v1/ws') {
      if (allowConnection) {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((_) {}, onDone: () => sockets.remove(socket));
        continue;
      }
      request.response.statusCode = HttpStatus.serviceUnavailable;
    } else if (request.uri.path == '/health') {
      request.response.write('{"status":"ok"}');
    } else if (request.method == 'POST') {
      await request.drain<void>();
      request.response.statusCode = HttpStatus.created;
    } else {
      request.response.write('[]');
    }
    await request.response.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native connection events reach the service through FFI and survive recreation',
    () async {
      final output = ReceivePort();
      final responses = StreamIterator<dynamic>(output);
      final server = await Isolate.spawn(_serve, output.sendPort);
      final directory = await Directory.systemTemp.createTemp('huginn-status-');
      final service = MessengerService();
      addTearDown(() async {
        service.dispose();
        server.kill(priority: Isolate.immediate);
        await responses.cancel();
        output.close();
        await directory.delete(recursive: true);
      });
      await responses.moveNext();
      final setup = responses.current as List;
      final address = setup[0] as String;
      final commands = setup[1] as SendPort;

      Future<void> command(String command) async {
        commands.send(command);
        await responses.moveNext().timeout(const Duration(seconds: 5));
        expect(responses.current, command);
      }

      Future<void> waitForState(MuninnConnectionState state) async {
        if (service.muninnConnectionState != state) {
          await service.events
              .firstWhere(
                (event) =>
                    event is MuninnConnectionEvent && event.state == state,
              )
              .timeout(const Duration(seconds: 15));
        }
        expect(service.muninnConnectionState, state);
      }

      expect(
        await service.init(
          username: 'alice',
          muninnAddr: address,
          dbPath: '${directory.path}/huginn.db',
        ),
        isTrue,
      );
      expect(service.muninnConnectionState, MuninnConnectionState.connecting);
      await command('connect');
      await waitForState(MuninnConnectionState.connected);
      await command('disconnect');
      await waitForState(MuninnConnectionState.connecting);
      await command('connect');
      await waitForState(MuninnConnectionState.connected);

      await command('disconnect');
      expect(await service.setUsername('bob'), isTrue);
      expect(service.muninnConnectionState, MuninnConnectionState.connecting);
      await command('connect');
      await waitForState(MuninnConnectionState.connected);
    },
    skip: Platform.environment['HUGINN_NATIVE_TESTS'] != '1',
  );
}
