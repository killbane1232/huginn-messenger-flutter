import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/huginn_messenger.dart';
import 'package:huginn_messenger/main.dart';
import 'package:huginn_messenger/src/widgets/downloads_screen.dart';
import 'package:huginn_messenger/src/widgets/muninn_connection_indicator.dart';

class _Messenger extends MessengerService {
  final updates = StreamController<AppEvent>.broadcast();
  MuninnConnectionState state = MuninnConnectionState.connecting;

  @override
  MuninnConnectionState get muninnConnectionState => state;

  @override
  Stream<AppEvent> get events => updates.stream;

  void changeState(MuninnConnectionState value) {
    state = value;
    updates.add(MuninnConnectionEvent(value));
  }

  @override
  void dispose() {
    updates.close();
    super.dispose();
  }
}

void main() {
  late _Messenger service;
  setUp(() => service = _Messenger());
  tearDown(() => service.dispose());

  for (final screen in ['home', 'chat', 'settings', 'downloads', 'login']) {
    testWidgets('$screen shows connection, loss and recovery', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: switch (screen) {
            'home' => HomeScreen(service: service),
            'chat' => ChatScreen(
              service: service,
              peerId: 'bob',
              peerName: 'Bob',
              isGroup: true,
            ),
            'settings' => SettingsScreen(service: service),
            'downloads' => DownloadsScreen(service: service),
            _ => FirstLoginScreen(service: service, onComplete: () {}),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connecting to Muninn…'), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsOneWidget);

      service.changeState(MuninnConnectionState.connected);
      await tester.pumpAndSettle();
      expect(find.text('Connected to Muninn'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
      expect(find.text('Connecting to Muninn…'), findsNothing);

      service.changeState(MuninnConnectionState.connecting);
      await tester.pumpAndSettle();
      expect(find.text('Connected to Muninn'), findsNothing);
      expect(find.text('Connecting to Muninn…'), findsOneWidget);

      service.changeState(MuninnConnectionState.connected);
      await tester.pumpAndSettle();
      expect(find.text('Connected to Muninn'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'new indicator reads current status without waiting for an event',
    (tester) async {
      service.changeState(MuninnConnectionState.connected);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MuninnConnectionIndicator(service: service)),
        ),
      );
      expect(find.text('Connected to Muninn'), findsOneWidget);
      service.changeState(MuninnConnectionState.disconnected);
      await tester.pumpAndSettle();
      expect(find.text('Muninn: not connected'), findsOneWidget);
    },
  );
}
