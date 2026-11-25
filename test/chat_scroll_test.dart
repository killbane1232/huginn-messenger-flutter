import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/huginn_messenger.dart';
import 'package:huginn_messenger/main.dart';

class _Messenger extends MessengerService {
  final updates = StreamController<AppEvent>.broadcast();
  List<ChatMessage> messages = [];
  Completer<List<ChatMessage>>? initial;
  Completer<List<ChatMessage>>? older;
  final offsets = <int>[];

  @override
  Stream<AppEvent> get events => updates.stream;

  @override
  Future<List<ChatMessage>> getMessagesPaginated(
    String peerId, {
    int limit = 64,
    int offset = 0,
  }) async {
    offsets.add(offset);
    if (offset == 0) return initial?.future ?? List.of(messages);
    return older?.future ?? <ChatMessage>[];
  }

  @override
  void dispose() {
    updates.close();
    super.dispose();
  }
}

ChatMessage _message(int index) => ChatMessage(
  msgId: 'message-$index',
  chatId: 'alice',
  from: 'alice',
  // Uneven row heights expose jumps based on an estimated maxScrollExtent.
  text: 'Message $index${'\nExtra line' * (index % 7)}',
  timestamp: DateTime(2026, 11, 25, 12, index),
);

void main() {
  late _Messenger service;
  setUp(() => service = _Messenger());
  tearDown(() => service.dispose());

  Widget chat() => ChatScreen(
    key: const PageStorageKey('alice'),
    service: service,
    peerId: 'alice',
    peerName: 'Alice',
  );

  Future<void> showChat(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.android,
    Widget? home,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: home ?? chat(),
      ),
    );
    // A pending history request intentionally keeps the loading spinner active.
    if (service.initial == null) await tester.pumpAndSettle();
  }

  Finder message(int index) => find.text(_message(index).text);

  Finder getInput() => find.widgetWithText(TextField, 'Type a message...');

  ScrollPosition position(WidgetTester tester) =>
      tester.widget<ListView>(find.byType(ListView)).controller!.position;

  void expectLatestVisible(WidgetTester tester, int index) {
    expect(message(index).hitTestable(), findsOneWidget);
    final viewport = tester.getRect(find.byType(ListView));
    expect(tester.getBottomRight(message(index)).dy, lessThan(viewport.bottom));
  }

  testWidgets('first history frame shows the latest variable-height message', (
    tester,
  ) async {
    service.initial = Completer<List<ChatMessage>>();
    await showChat(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    service.initial!.complete(List.generate(64, _message));
    await tester.pump();
    await tester.pump();
    expectLatestVisible(tester, 63);
    await tester.pumpAndSettle();
    expectLatestVisible(tester, 63);
    expect(service.offsets, [0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reopening a conversation always returns to the latest message', (
    tester,
  ) async {
    service.messages = List.generate(64, _message);
    await showChat(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => chat())),
              child: const Text('Open chat'),
            ),
          ),
        ),
      ),
    );
    for (var visit = 0; visit < 2; visit++) {
      await tester.tap(find.text('Open chat'));
      await tester.pumpAndSettle();
      expectLatestVisible(tester, 63);
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(message(63).hitTestable(), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(service.offsets, [0, 0]);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final count in [3, 64]) {
      testWidgets('$platform keeps $count messages at the composer on resize', (
        tester,
      ) async {
        service.messages = List.generate(count, _message);
        await showChat(tester, platform: platform);
        final latest = message(count - 1);
        expectLatestVisible(tester, count - 1);
        final gap =
            tester.getTopLeft(getInput()).dy - tester.getBottomRight(latest).dy;
        await tester.tap(getInput());

        void expectAnchored() {
          expectLatestVisible(tester, count - 1);
          expect(
            tester.getTopLeft(getInput()).dy - tester.getBottomRight(latest).dy,
            closeTo(gap, 0.01),
          );
          expect(tester.takeException(), isNull);
        }

        // Check each keyboard animation step, not just the settled position.
        for (final inset in [100.0, 200.0, 300.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          await tester.pump();
          expectAnchored();
        }
        await tester.enterText(getInput(), 'One\nTwo\nThree');
        await tester.pumpAndSettle();
        expectAnchored();
        for (final inset in [200.0, 100.0, 0.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          await tester.pump();
          expectAnchored();
        }
        expect(service.offsets, [0]);
      });
    }
  }

  testWidgets(
    'opening the keyboard while reading history does not jump to end',
    (tester) async {
      service.messages = List.generate(64, _message);
      await showChat(tester);
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(message(63).hitTestable(), findsNothing);
      final oldOffset = position(tester).pixels;
      await tester.tap(getInput());
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(position(tester).pixels, closeTo(oldOffset, 0.01));
      expect(message(63).hitTestable(), findsNothing);
      expect(service.offsets, [0]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('new messages reach the end with the keyboard open', (
    tester,
  ) async {
    service.messages = List.generate(64, _message);
    await showChat(tester);
    await tester.tap(getInput());
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    service.updates.add(MessageEvent(_message(64)));
    await tester.pumpAndSettle();
    expectLatestVisible(tester, 64);

    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(message(64).hitTestable(), findsNothing);
    service.updates.add(MessageEvent(_message(65)));
    await tester.pumpAndSettle();
    expectLatestVisible(tester, 65);
    expect(service.offsets, [0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading older messages preserves the visible history position', (
    tester,
  ) async {
    service.messages = List.generate(64, (index) => _message(index + 64));
    service.older = Completer<List<ChatMessage>>();
    await showChat(tester);
    await tester.dragUntilVisible(
      message(64),
      find.byType(ListView),
      const Offset(0, 400),
      maxIteration: 100,
    );
    await tester.pump();
    expect(service.offsets, [0, 64]);
    final anchor = message(65);
    expect(anchor.hitTestable(), findsOneWidget);
    final before = tester.getTopLeft(anchor);
    service.older!.complete(List.generate(64, _message));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(anchor).dy, closeTo(before.dy, 0.01));
    expect(message(127).hitTestable(), findsNothing);
    expect(service.offsets, [0, 64]);
    expect(tester.takeException(), isNull);
  });
}
