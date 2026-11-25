import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/huginn_messenger.dart';
import 'package:huginn_messenger/main.dart';
import 'package:huginn_messenger/src/models/file_download.dart';
import 'package:huginn_messenger/src/widgets/downloads_screen.dart';

class _Messenger extends MessengerService {
  int saves = 0;

  @override
  AppConfig get config =>
      AppConfig(username: 'alice', muninnAddr: 'https://muninn.example');

  @override
  bool saveConfig(AppConfig config) {
    saves++;
    return true;
  }

  @override
  List<Peer> get peers => [Peer(login: 'Bob')];

  @override
  List<Peer> getPeers() => peers;

  @override
  Future<List<FileDownload>> getFileDownloads() async => [
    FileDownload(
      fileId: 'file',
      filename: 'document.txt',
      receivedChunks: 1,
      totalChunks: 4,
    ),
  ];
}

void main() {
  late _Messenger service;
  setUp(() => service = _Messenger());
  tearDown(() => service.dispose());

  void setSystemInsets(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    double bottom = 48,
    double left = 0,
    double right = 0,
    double keyboard = 0,
  }) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewPadding = FakeViewPadding(
      top: 24,
      bottom: bottom,
      left: left,
      right: right,
    );
    tester.view.padding = FakeViewPadding(
      top: 24,
      bottom: keyboard > 0 ? 0 : bottom,
      left: left,
      right: right,
    );
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  }

  Future<void> showScreen(WidgetTester tester, Widget screen) async {
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: screen,
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final bottom in [0.0, 24.0, 48.0]) {
    testWidgets('chat respects $bottom inset and keyboard transitions', (
      tester,
    ) async {
      setSystemInsets(tester, bottom: bottom);
      await showScreen(
        tester,
        ChatScreen(service: service, peerId: 'bob', peerName: 'Bob'),
      );
      final send = find.widgetWithIcon(FilledButton, Icons.send);
      final input = find.widgetWithText(TextField, 'Type a message...');
      final initialBottom = tester.getBottomRight(send).dy;
      expect(initialBottom, closeTo(800 - bottom - 12, 0.01));
      expect(tester.getBottomRight(input).dy, lessThanOrEqualTo(800 - bottom));

      await tester.tap(input);
      setSystemInsets(tester, bottom: bottom, keyboard: 300);
      await tester.pumpAndSettle();
      await tester.enterText(input, 'Message\nwith two lines');
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(send).dy, closeTo(800 - 300 - 12, 0.01));
      expect(tester.getBottomRight(input).dy, lessThanOrEqualTo(800 - 300));

      setSystemInsets(tester, bottom: bottom);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(send).dy, closeTo(initialBottom, 0.01));
      expect(find.text('Message\nwith two lines'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('chat avoids navigation buttons on either landscape edge', (
    tester,
  ) async {
    setSystemInsets(tester);
    await showScreen(
      tester,
      ChatScreen(service: service, peerId: 'bob', peerName: 'Bob'),
    );
    for (final left in [false, true]) {
      setSystemInsets(
        tester,
        size: const Size(800, 400),
        bottom: 0,
        left: left ? 48 : 0,
        right: left ? 0 : 48,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byTooltip('Attach file')).dx,
        greaterThanOrEqualTo(left ? 48 : 0),
      );
      expect(
        tester.getBottomRight(find.widgetWithIcon(FilledButton, Icons.send)).dx,
        lessThanOrEqualTo(left ? 800 : 752),
      );
      expect(tester.takeException(), isNull);
    }
  });

  for (final screen in ['home', 'settings', 'downloads']) {
    testWidgets('$screen content stays clear of system navigation', (
      tester,
    ) async {
      setSystemInsets(tester, left: 16, right: 16);
      await showScreen(tester, switch (screen) {
        'home' => HomeScreen(service: service),
        'settings' => SettingsScreen(service: service),
        _ => DownloadsScreen(service: service),
      });
      final viewport = tester.getRect(find.byType(ListView));
      expect(viewport.bottom, closeTo(752, 0.01));
      expect(viewport.left, greaterThanOrEqualTo(16));
      expect(viewport.right, lessThanOrEqualTo(384));
      final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
      if (screen == 'home') {
        expect(viewport.top, greaterThan(appBarBottom));
      } else {
        expect(viewport.top, closeTo(appBarBottom, 0.01));
      }

      if (screen == 'settings') {
        final save = find.widgetWithText(FilledButton, 'Save');
        await tester.scrollUntilVisible(
          save,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(752));
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(service.saves, 1);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
