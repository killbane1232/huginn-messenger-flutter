import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/src/services/macos_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MacOSNotificationService service;
  late List<MethodCall> calls;
  late bool permitted;
  late bool requestGranted;
  Map<String, Object?>? launch;

  setUp(() {
    service = MacOSNotificationService();
    calls = [];
    permitted = true;
    requestGranted = false;
    launch = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
        case 'openAppNotificationSettings':
          return true;
        case 'checkPermissions':
          return {'isEnabled': permitted};
        case 'requestPermissions':
          permitted = requestGranted;
          return requestGranted;
        case 'getNotificationAppLaunchDetails':
          return launch;
        case 'show':
          return null;
        default:
          throw StateError('Unexpected notification call: ${call.method}');
      }
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'requests alerts and sound when not authorized; denial suppresses messages',
    () async {
      permitted = false;
      await service.init(onNotificationTap: (_) {});
      expect(service.notificationsEnabled, isFalse);
      final request = calls.singleWhere(
        (call) => call.method == 'requestPermissions',
      );
      expect(request.arguments['alert'], isTrue);
      expect(request.arguments['sound'], isTrue);
      expect(request.arguments['badge'], isFalse);
      await service.showMessage(
        chatId: 'chat',
        peerName: 'Alice',
        text: 'Hello',
      );
      expect(calls.where((call) => call.method == 'show'), isEmpty);
    },
  );

  test(
    'granted permission permits banners and preserves the full chat key',
    () async {
      permitted = false;
      requestGranted = true;
      await service.init(onNotificationTap: (_) {});
      expect(service.notificationsEnabled, isTrue);
      await service.showMessage(
        chatId: 'alice:signature-key',
        peerName: 'Alice',
        text: 'Hello',
      );
      final show =
          calls.singleWhere((call) => call.method == 'show').arguments as Map;
      expect(show['title'], 'Alice');
      expect(show['body'], 'Hello');
      expect(show['payload'], 'alice:signature-key');
      expect(show['id'], inInclusiveRange(0, 0x7fffffff));
      final details = show['platformSpecifics'] as Map;
      expect(details['presentBanner'], isTrue);
      expect(details['presentList'], isTrue);
      expect(details['presentSound'], isTrue);
      expect(details['threadIdentifier'], 'alice:signature-key');
    },
  );

  test(
    'existing authorization does not prompt; settings changes apply immediately',
    () async {
      await service.init(onNotificationTap: (_) {});
      expect(
        calls.where((call) => call.method == 'requestPermissions'),
        isEmpty,
      );
      permitted = false;
      await service.showMessage(
        chatId: 'chat',
        peerName: 'Alice',
        text: 'Blocked',
      );
      expect(service.notificationsEnabled, isFalse);
      expect(calls.where((call) => call.method == 'show'), isEmpty);
      permitted = true;
      await service.showMessage(
        chatId: 'chat',
        peerName: 'Alice',
        text: 'Allowed',
      );
      expect(service.notificationsEnabled, isTrue);
      expect(
        calls.singleWhere((call) => call.method == 'show').arguments['body'],
        'Allowed',
      );
    },
  );

  test(
    'notification taps route to the chat and ignore empty payloads',
    () async {
      final chats = <String>[];
      await service.init(onNotificationTap: chats.add);
      for (final payload in [' group-uid ', '', null]) {
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('didReceiveNotificationResponse', {
              'notificationId': 1,
              'notificationResponseType': 0,
              'payload': payload,
            }),
          ),
          (_) {},
        );
      }
      expect(chats, ['group-uid']);
    },
  );

  test('cold launch returns the notification chat key', () async {
    launch = {
      'notificationLaunchedApp': true,
      'notificationResponse': {
        'notificationId': 1,
        'notificationResponseType': 0,
        'payload': ' alice:signature-key ',
      },
    };
    expect(
      await service.init(onNotificationTap: (_) {}),
      'alice:signature-key',
    );
  });

  test('opens notification System Settings', () async {
    expect(await service.openSettings(), isTrue);
    expect(calls.single.method, 'openAppNotificationSettings');
  });

  test('messages arriving before initialization are safely skipped', () async {
    await service.showMessage(chatId: 'chat', peerName: 'Alice', text: 'Hello');
    expect(calls, isEmpty);
  });
}
