import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/huginn_messenger.dart';
import 'package:huginn_messenger/main.dart';

class _FakeMessengerService extends MessengerService {
  final peerEvents = StreamController<List<Peer>>.broadcast();
  final messageEvents = StreamController<AppEvent>.broadcast();
  List<Peer> peerList = [];
  List<Peer> searchResults = [];
  final history = <String, ChatMessage>{};
  final historyRequests = <({String peerId, int limit, int offset})>[];
  final pendingHistory = <String, Completer<List<ChatMessage>>>{};

  @override
  List<Peer> get peers => peerList;

  @override
  List<Peer> getPeers() => peerList;

  @override
  List<GroupChat> getGroups() => [];

  @override
  Stream<List<Peer>> get peersStream => peerEvents.stream;

  @override
  Stream<AppEvent> get events => messageEvents.stream;

  @override
  List<Peer> searchPeers(String query) => searchResults;

  @override
  void refreshPeers() => peerEvents.add(peerList);

  @override
  Future<List<ChatMessage>> getMessagesPaginated(
    String peerId, {
    int limit = 64,
    int offset = 0,
  }) async {
    historyRequests.add((peerId: peerId, limit: limit, offset: offset));
    final pending = pendingHistory.remove(peerId);
    if (pending != null) return pending.future;
    final message = history[peerId];
    return message == null ? [] : [message];
  }

  @override
  void dispose() {
    peerEvents.close();
    messageEvents.close();
    super.dispose();
  }
}

ChatMessage _message(
  Peer peer,
  String text,
  String timestamp, {
  String? from,
  String? chatId,
}) => ChatMessage(
  from: from ?? peer.displayLogin,
  chatId: chatId ?? peer.key,
  text: text,
  timestamp: DateTime.parse(timestamp),
);

List<String> _peerOrder(WidgetTester tester) => tester
    .widgetList<ListTile>(find.byType(ListTile))
    .map((tile) => (tile.key! as ValueKey<String>).value)
    .toList();

void main() {
  late _FakeMessengerService service;
  final alice = Peer(login: 'Alice', signatureKey: 'alice-key');
  final bob = Peer(login: 'Bob:bob-key', signatureKey: 'bob-key');
  final charlie = Peer(login: 'Charlie', online: true);

  setUp(() => service = _FakeMessengerService());
  tearDown(() => service.dispose());

  Future<void> showHome(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: HomeScreen(service: service)));
    await tester.pumpAndSettle();
  }

  testWidgets('loads last messages and sorts by full timestamp, then name', (
    tester,
  ) async {
    final delta = Peer(login: 'Delta');
    final echo = Peer(login: 'Echo');
    service.peerList = [charlie, echo, alice, delta, bob];
    service.history[alice.key] = _message(
      alice,
      'Previous day',
      '2026-09-19T23:59:00Z',
    );
    service.history[bob.key] = _message(
      bob,
      'Latest message',
      '2026-09-20T10:30:00+03:00',
    );
    service.history[delta.key] = _message(
      delta,
      'Same instant',
      '2026-09-20T07:30:00Z',
    );

    await showHome(tester);

    expect(_peerOrder(tester), [
      bob.key,
      delta.key,
      alice.key,
      charlie.key,
      echo.key,
    ]);
    expect(find.text('Latest message'), findsOneWidget);
    expect(find.text('Previous day'), findsOneWidget);
    expect(find.text('No messages yet'), findsNWidgets(2));
    expect(service.peerList.first, charlie);
    expect(service.historyRequests, hasLength(5));
    expect(
      service.historyRequests.every((r) => r.limit == 1 && r.offset == 0),
      isTrue,
    );
  });

  testWidgets('incoming and outgoing events reorder chats; old events do not', (
    tester,
  ) async {
    service.peerList = [alice, bob];
    service.history[alice.key] = _message(
      alice,
      'Initial',
      '2026-09-20T10:00:00Z',
    );
    await showHome(tester);

    service.messageEvents.add(
      MessageEvent(_message(bob, 'Incoming', '2026-09-20T10:01:00Z')),
    );
    await tester.pumpAndSettle();
    expect(_peerOrder(tester), [bob.key, alice.key]);
    expect(find.text('Incoming'), findsOneWidget);

    service.messageEvents.add(
      MessageEvent(
        _message(alice, 'Outgoing', '2026-09-20T10:02:00Z', from: 'me'),
      ),
    );
    await tester.pumpAndSettle();
    expect(_peerOrder(tester), [alice.key, bob.key]);
    expect(find.text('Outgoing'), findsOneWidget);

    service.messageEvents.add(
      MessageEvent(_message(alice, 'Delayed', '2026-09-20T09:00:00Z')),
    );
    service.messageEvents.add(
      MessageEvent(
        _message(
          bob,
          'Group message',
          '2026-09-20T10:03:00Z',
          chatId: 'group-id',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_peerOrder(tester), [alice.key, bob.key]);
    expect(find.text('Outgoing'), findsOneWidget);
    expect(find.text('Incoming'), findsOneWidget);
    expect(find.text('Delayed'), findsNothing);
    expect(find.text('Group message'), findsNothing);
    expect(service.historyRequests, hasLength(2));
  });

  testWidgets('a pending history read cannot overwrite a newer event', (
    tester,
  ) async {
    service.peerList = [alice, bob];
    final pending = Completer<List<ChatMessage>>();
    service.pendingHistory[alice.key] = pending;
    await showHome(tester);

    service.messageEvents.add(
      MessageEvent(_message(alice, 'Live', '2026-09-20T10:02:00Z')),
    );
    await tester.pumpAndSettle();
    pending.complete([
      _message(alice, 'Stale history', '2026-09-20T10:00:00Z'),
    ]);
    await tester.pumpAndSettle();

    expect(_peerOrder(tester), [alice.key, bob.key]);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Stale history'), findsNothing);
  });

  testWidgets('loads new peers without reloading history on presence updates', (
    tester,
  ) async {
    service.peerList = [alice];
    await showHome(tester);
    service.history[bob.key] = _message(
      bob,
      'Discovered chat',
      '2026-09-20T10:00:00Z',
    );
    service.peerList = [alice, bob];
    service.refreshPeers();
    await tester.pumpAndSettle();

    expect(_peerOrder(tester), [bob.key, alice.key]);
    expect(find.text('Discovered chat'), findsOneWidget);
    service.peerList = [bob, alice];
    service.refreshPeers();
    await tester.pumpAndSettle();
    expect(_peerOrder(tester), [bob.key, alice.key]);
    expect(service.historyRequests, hasLength(2));
  });

  testWidgets('search results load previews and continue receiving updates', (
    tester,
  ) async {
    service.peerList = [alice];
    service.searchResults = [alice, bob];
    service.history[bob.key] = _message(
      bob,
      'Found chat',
      '2026-09-20T10:00:00Z',
    );
    await showHome(tester);
    await tester.enterText(find.byType(TextField), 'some search');
    await tester.pumpAndSettle();
    expect(_peerOrder(tester), [bob.key, alice.key]);
    expect(find.text('Found chat'), findsOneWidget);

    service.refreshPeers();
    service.messageEvents.add(
      MessageEvent(_message(alice, 'Search update', '2026-09-20T11:00:00Z')),
    );
    await tester.pumpAndSettle();
    expect(_peerOrder(tester), [alice.key, bob.key]);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(_peerOrder(tester), [alice.key]);
    expect(find.text('Search update'), findsOneWidget);
  });

  testWidgets('refresh reloads the latest saved messages', (tester) async {
    service.peerList = [alice, bob];
    service.history[alice.key] = _message(
      alice,
      'Initial',
      '2026-09-20T10:00:00Z',
    );
    await showHome(tester);
    service.history[bob.key] = _message(
      bob,
      'Saved later',
      '2026-09-20T11:00:00Z',
    );

    final refresh = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show();
    await tester.pumpAndSettle();
    await refresh;

    expect(_peerOrder(tester), [bob.key, alice.key]);
    expect(find.text('Saved later'), findsOneWidget);
  });

  testWidgets('legacy events use stored chat identity rather than sender', (
    tester,
  ) async {
    service.peerList = [alice, bob];
    await showHome(tester);
    service.history[bob.key] = _message(
      bob,
      'Legacy outgoing',
      '2026-09-20T11:00:00Z',
      from: 'me',
      chatId: '',
    );
    service.messageEvents.add(MessageEvent(service.history[bob.key]!));
    await tester.pumpAndSettle();
    expect(_peerOrder(tester), [bob.key, alice.key]);
    expect(find.text('Legacy outgoing'), findsOneWidget);

    service.messageEvents.add(
      MessageEvent(
        _message(alice, 'Unrelated group', '2026-09-20T12:00:00Z', chatId: ''),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unrelated group'), findsNothing);
    expect(_peerOrder(tester), [bob.key, alice.key]);
  });

  testWidgets('legacy events refresh chats hidden by the search filter', (
    tester,
  ) async {
    service.peerList = [alice, bob];
    service.searchResults = [alice];
    await showHome(tester);
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pumpAndSettle();
    service.history[bob.key] = _message(
      bob,
      'Hidden update',
      '2026-09-20T11:00:00Z',
      from: 'me',
      chatId: '',
    );
    service.messageEvents.add(MessageEvent(service.history[bob.key]!));
    await tester.pumpAndSettle();
    expect(_peerOrder(tester), [alice.key]);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(_peerOrder(tester), [bob.key, alice.key]);
    expect(find.text('Hidden update'), findsOneWidget);
  });

  testWidgets('shows one-line attachment previews and strips reply metadata', (
    tester,
  ) async {
    service.peerList = [alice, bob];
    service.history[alice.key] = ChatMessage(
      from: alice.displayLogin,
      chatId: alice.key,
      text: '',
      timestamp: DateTime.utc(2026, 9, 20),
      files: [FileMeta(fileId: 'file', filename: 'report.pdf')],
    );
    service.history[bob.key] = _message(
      bob,
      FormattedMessageText.encodeReply(
        author: 'me',
        preview: 'Quoted',
        body: 'Answer\nSecond line',
      ),
      '2026-09-20T11:00:00Z',
    );
    await showHome(tester);

    expect(find.text('[File: report.pdf]'), findsOneWidget);
    expect(find.text('Answer'), findsOneWidget);
    final preview = tester.widget<Text>(find.text('Answer'));
    expect(preview.maxLines, 1);
    expect(preview.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ignores pending history after the home screen is disposed', (
    tester,
  ) async {
    service.peerList = [alice];
    final pending = Completer<List<ChatMessage>>();
    service.pendingHistory[alice.key] = pending;
    await showHome(tester);
    await tester.pumpWidget(const SizedBox());
    pending.complete([_message(alice, 'Too late', '2026-09-20T10:00:00Z')]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
