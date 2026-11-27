import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/huginn_messenger.dart';
import 'package:huginn_messenger/main.dart';

class _Messenger extends MessengerService {
  final updates = StreamController<AppEvent>.broadcast();
  final messages = <ChatMessage>[];
  final deleted = <String>[];
  final retried = <String>[];
  bool retrySucceeds = true;
  bool deleteSucceeds = true;

  @override
  String get currentUsername => 'me';

  @override
  Stream<AppEvent> get events => updates.stream;

  @override
  Future<List<ChatMessage>> getMessagesPaginated(
    String peerId, {
    int limit = 64,
    int offset = 0,
  }) async => List.of(messages);

  @override
  bool sendMessage(String to, String text, {int ttl = 0}) {
    final message = _failedMessage(text: text);
    messages.add(message);
    updates.add(MessageEvent(message));
    return true;
  }

  @override
  bool deleteFailedMessage(String chatId, String msgId) {
    deleted.add(msgId);
    if (!deleteSucceeds) return false;
    messages.removeWhere((message) => message.msgId == msgId);
    updates.add(MessageDeletedEvent(chatId, msgId));
    return true;
  }

  @override
  ChatMessage? retryMessage(String msgId) {
    retried.add(msgId);
    if (!retrySucceeds) return null;
    final index = messages.indexWhere((message) => message.msgId == msgId);
    final previous = messages[index];
    final sent = ChatMessage(
      from: previous.from,
      chatId: previous.chatId,
      text: previous.text,
      timestamp: previous.timestamp,
      msgId: previous.msgId,
      files: previous.files,
    );
    messages[index] = sent;
    updates.add(MessageEvent(sent));
    return sent;
  }

  @override
  void dispose() {
    updates.close();
    super.dispose();
  }
}

ChatMessage _failedMessage({
  String text = 'Unsent message',
  bool file = false,
}) => ChatMessage(
  from: 'me',
  chatId: 'alice',
  msgId: 'failed-id',
  text: text,
  timestamp: DateTime(2026, 11, 27, 12),
  sendError: 'recipient not found',
  files: file
      ? [
          FileMeta(
            fileId: 'file',
            filename: 'report.pdf',
            filePath: '/report.pdf',
          ),
        ]
      : [],
);

void main() {
  late _Messenger service;
  setUp(() => service = _Messenger());
  tearDown(() => service.dispose());

  Future<void> showChat(WidgetTester tester, TargetPlatform platform) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: ChatScreen(service: service, peerId: 'alice', peerName: 'Alice'),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('stored failure preserves status and attachments in JSON', () {
    final original = _failedMessage(file: true);
    final restored = ChatMessage.fromJson(original.toJson());
    expect(restored.sendFailed, isTrue);
    expect(restored.sendError, 'recipient not found');
    expect(restored.files.single.filePath, '/report.pdf');
    expect(ChatMessage.fromJson({'text': 'old message'}).sendFailed, isFalse);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets(
      'tap opens failure actions and delete removes it on $platform',
      (tester) async {
        final failed = _failedMessage();
        service.messages.add(failed);
        await showChat(tester, platform);
        expect(find.text('Не отправлено'), findsOneWidget);
        await tester.tapAt(tester.getCenter(find.text('Unsent message')));
        await tester.pumpAndSettle();
        expect(find.text('Удалить'), findsOneWidget);
        expect(find.text('Переотправить'), findsOneWidget);
        expect(find.text('Reply'), findsNothing);
        await tester.tap(find.text('Удалить'));
        await tester.pumpAndSettle();
        expect(service.deleted, ['failed-id']);
        expect(find.text('Unsent message'), findsNothing);
        service.updates.add(MessageEvent(failed));
        await tester.pumpAndSettle();
        expect(find.text('Unsent message'), findsNothing);
        expect(find.text('No messages yet'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'successful retry updates the same bubble and ignores stale failure',
    (tester) async {
      final failed = _failedMessage();
      service.messages.add(failed);
      await showChat(tester, TargetPlatform.macOS);
      await tester.tapAt(tester.getCenter(find.text('Не отправлено')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Переотправить'));
      await tester.pumpAndSettle();
      expect(service.retried, ['failed-id']);
      expect(find.text('Unsent message'), findsOneWidget);
      expect(find.text('Не отправлено'), findsNothing);
      service.updates.add(MessageEvent(failed));
      await tester.pumpAndSettle();
      expect(find.text('Unsent message'), findsOneWidget);
      expect(find.text('Не отправлено'), findsNothing);
    },
  );

  testWidgets('failed retry and failed deletion retain the message', (
    tester,
  ) async {
    service.messages.add(_failedMessage());
    service.retrySucceeds = false;
    service.deleteSucceeds = false;
    await showChat(tester, TargetPlatform.android);
    for (final action in ['Переотправить', 'Удалить']) {
      await tester.tapAt(tester.getCenter(find.text('Unsent message')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(find.text('Unsent message'), findsOneWidget);
      expect(find.text('Не отправлено'), findsOneWidget);
    }
  });

  testWidgets('stored send clears composer and appears as a failed message', (
    tester,
  ) async {
    await showChat(tester, TargetPlatform.android);
    final input = find.widgetWithText(TextField, 'Type a message...');
    await tester.enterText(input, 'Keep my text');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(find.text('Keep my text'), findsOneWidget);
    expect(find.text('Не отправлено'), findsOneWidget);
    expect(find.text('recipient not found'), findsNothing);
  });

  testWidgets('tapping a failed attachment opens the failure menu', (
    tester,
  ) async {
    service.messages.add(_failedMessage(text: '', file: true));
    await showChat(tester, TargetPlatform.macOS);
    await tester.tapAt(tester.getCenter(find.text('report.pdf')));
    await tester.pumpAndSettle();
    expect(find.text('Удалить'), findsOneWidget);
    expect(find.text('Переотправить'), findsOneWidget);
  });
}
