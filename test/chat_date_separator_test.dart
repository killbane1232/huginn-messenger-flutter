import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/huginn_messenger.dart';
import 'package:huginn_messenger/main.dart';
import 'package:huginn_messenger/src/widgets/chat_date_separator.dart';

class _Messenger extends MessengerService {
  final updates = StreamController<AppEvent>.broadcast();
  List<ChatMessage> messages = [];
  Completer<List<ChatMessage>>? older;
  final offsets = <int>[];

  @override
  String get currentUsername => 'me';

  @override
  Stream<AppEvent> get events => updates.stream;

  @override
  Future<List<ChatMessage>> getMessagesPaginated(
    String peerId, {
    int limit = 64,
    int offset = 0,
  }) async {
    offsets.add(offset);
    return offset == 0 ? List.of(messages) : await older!.future;
  }

  @override
  void dispose() {
    updates.close();
    super.dispose();
  }
}

void main() {
  late _Messenger service;
  final year = DateTime.now().year;
  setUp(() => service = _Messenger());
  tearDown(() => service.dispose());

  ChatMessage message(String id, DateTime date, {bool own = false}) =>
      ChatMessage(
        msgId: id,
        chatId: 'alice',
        from: own ? 'me' : 'alice',
        text: id,
        timestamp: date,
      );

  Future<void> showChat(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          platform: TargetPlatform.android,
          brightness: brightness,
        ),
        home: ChatScreen(service: service, peerId: 'alice', peerName: 'Alice'),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets('centers one pill per day in $brightness', (tester) async {
      service.messages = [
        message('First message', DateTime(year, 11, 20, 12, 18)),
        message('Reply', DateTime(year, 11, 20, 23, 50), own: true),
        message('Next day', DateTime(year, 11, 21, 0, 2)),
      ];
      await showChat(tester, brightness: brightness);
      expect(find.byType(ChatDateSeparator), findsNWidgets(2));
      for (final label in ['20 ноября', '21 ноября']) {
        expect(find.text(label), findsOneWidget);
        expect(tester.getCenter(find.text(label)).dx, closeTo(200, 0.01));
      }
      expect(
        tester.getBottomLeft(find.text('20 ноября')).dy,
        lessThan(tester.getTopLeft(find.text('First message')).dy),
      );
      expect(
        tester.getTopLeft(find.text('21 ноября')).dy,
        greaterThan(tester.getBottomLeft(find.text('Reply')).dy),
      );
      expect(
        tester.getBottomLeft(find.text('21 ноября')).dy,
        lessThan(tester.getTopLeft(find.text('Next day')).dy),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('groups UTC timestamps by local day and includes older years', (
    tester,
  ) async {
    service.messages = [
      message('Previous year', DateTime(year - 1, 12, 31, 23, 58).toUtc()),
      message('New year', DateTime(year, 1, 1, 0, 2).toUtc()),
      message('Same local day', DateTime(year, 1, 1, 12).toUtc()),
    ];
    await showChat(tester);
    expect(find.text('31 декабря ${year - 1}'), findsOneWidget);
    expect(find.text('1 января'), findsOneWidget);
    expect(find.byType(ChatDateSeparator), findsNWidgets(2));
    expect(find.text('23:58'), findsOneWidget);
    expect(find.text('00:02'), findsOneWidget);
  });

  testWidgets('adds dates for new and delayed messages without duplicates', (
    tester,
  ) async {
    service.messages = [message('First', DateTime(year, 11, 20, 12))];
    await showChat(tester);
    service.updates.add(
      MessageEvent(message('New', DateTime(year, 11, 21, 1))),
    );
    await tester.pumpAndSettle();
    service.updates.add(
      MessageEvent(message('Delayed', DateTime(year, 11, 20, 23))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChatDateSeparator), findsNWidgets(2));
    expect(find.text('20 ноября'), findsOneWidget);
    expect(find.text('21 ноября'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Delayed')).dy,
      lessThan(tester.getTopLeft(find.text('21 ноября')).dy),
    );
  });

  testWidgets('older pages merge a shared day at the pagination boundary', (
    tester,
  ) async {
    service.messages = List.generate(
      64,
      (index) => message('Recent $index', DateTime(year, 11, 20, 12, index)),
    );
    service.older = Completer<List<ChatMessage>>();
    await showChat(tester);
    final list = tester.widget<ListView>(find.byType(ListView));
    list.controller!.jumpTo(0);
    await tester.pump();
    expect(service.offsets, [0, 64]);
    expect(find.text('20 ноября'), findsOneWidget);
    service.older!.complete([
      message('Previous day', DateTime(year, 11, 19, 23, 59)),
      message('Earlier same day', DateTime(year, 11, 20, 0, 1)),
    ]);
    await tester.pumpAndSettle();
    list.controller!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('19 ноября'), findsOneWidget);
    expect(find.text('20 ноября'), findsOneWidget);
    expect(find.byType(ChatDateSeparator), findsNWidgets(2));
    expect(find.text('Recent 0'), findsOneWidget);
    expect(service.offsets, [0, 64]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty conversation has no date pill', (tester) async {
    await showChat(tester);
    expect(find.byType(ChatDateSeparator), findsNothing);
  });
}
