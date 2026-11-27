import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/huginn_messenger.dart';
import 'package:huginn_messenger/main.dart';

class _FakeMessengerService extends MessengerService {
  final peerEvents = StreamController<List<Peer>>.broadcast();
  final messageEvents = StreamController<AppEvent>.broadcast();
  List<Peer> peerList = [];
  List<Peer> searchResults = [];
  List<GroupChat> groupList = [];
  final hiddenChats = <String>{};
  final deletedChats = <String>[];
  bool deleteSucceeds = true;
  final history = <String, ChatMessage>{};
  final historyRequests = <({String peerId, int limit, int offset})>[];
  final pendingHistory = <String, Completer<List<ChatMessage>>>{};

  @override
  List<Peer> get peers => peerList;

  @override
  List<Peer> getPeers() => peerList;

  @override
  List<GroupChat> getGroups() => groupList;

  @override
  Set<String> getHiddenChatIds() => Set.of(hiddenChats);

  @override
  bool deleteChat(String chatId) {
    if (!deleteSucceeds) return false;
    deletedChats.add(chatId);
    hiddenChats.add(chatId);
    history.remove(chatId);
    return true;
  }

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

  Future<void> selectDelete(
    WidgetTester tester,
    String chatId, {
    bool secondary = false,
  }) async {
    final tile = find.byKey(ValueKey(chatId));
    if (secondary) {
      await tester.tap(tile, buttons: kSecondaryMouseButton);
    } else {
      await tester.longPress(tile);
    }
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text('Delete chat'), findsOneWidget);
    await tester.tap(find.text('Delete chat'));
    await tester.pumpAndSettle();
    expect(find.text('Delete chat?'), findsOneWidget);
    expect(service.deletedChats, isEmpty);
  }

  testWidgets('long press offers deletion and cancellation keeps history', (
    tester,
  ) async {
    service.peerList = [alice];
    service.history[alice.key] = _message(
      alice,
      'Keep me',
      '2026-11-25T10:00:00Z',
    );
    await showHome(tester);
    await selectDelete(tester, alice.key);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.deletedChats, isEmpty);
    expect(find.text('Keep me'), findsOneWidget);
    expect(find.byKey(ValueKey(alice.key)), findsOneWidget);
  });

  testWidgets('deleted peer stays hidden after refresh and reopening home', (
    tester,
  ) async {
    service.peerList = [alice, bob];
    service.history[alice.key] = _message(
      alice,
      'Old history',
      '2026-11-25T10:00:00Z',
    );
    await showHome(tester);
    await selectDelete(tester, alice.key);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(service.deletedChats, [alice.key]);
    expect(service.history[alice.key], isNull);
    expect(_peerOrder(tester), [bob.key]);
    service.refreshPeers();
    service.messageEvents.add(
      MessageEvent(_message(alice, 'Queued old event', '2026-11-25T10:00:00Z')),
    );
    await tester.pumpAndSettle();
    expect(_peerOrder(tester), [bob.key]);
    await tester.pumpWidget(const SizedBox());
    await showHome(tester);
    expect(_peerOrder(tester), [bob.key]);
    service.hiddenChats.remove(alice.key);
    service.messageEvents.add(
      MessageEvent(_message(alice, 'New message', '2026-11-25T11:00:00Z')),
    );
    await tester.pumpAndSettle();
    expect(_peerOrder(tester), [alice.key, bob.key]);
    expect(find.text('New message'), findsOneWidget);
    expect(find.text('Old history'), findsNothing);
  });

  testWidgets('secondary click deletes a group without deleting other chats', (
    tester,
  ) async {
    service.peerList = [alice];
    service.groupList = [GroupChat(uid: 'group-id', name: 'Friends')];
    await showHome(tester);
    await selectDelete(tester, 'group-id', secondary: true);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(service.deletedChats, ['group-id']);
    expect(find.text('Friends'), findsNothing);
    expect(find.byKey(ValueKey(alice.key)), findsOneWidget);
    service.refreshPeers();
    service.messageEvents.add(
      MessageEvent(_message(alice, 'Hello', '2026-11-25T11:00:00Z')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Friends'), findsNothing);
    service.hiddenChats.remove('group-id');
    service.messageEvents.add(
      MessageEvent(
        _message(
          alice,
          'Group message',
          '2026-11-25T12:00:00Z',
          chatId: 'group-id',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Friends'), findsOneWidget);
  });

  testWidgets('failed deletion keeps the conversation and reports the error', (
    tester,
  ) async {
    service.peerList = [alice];
    service.deleteSucceeds = false;
    await showHome(tester);
    await selectDelete(tester, alice.key, secondary: true);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey(alice.key)), findsOneWidget);
    expect(find.text('Failed to delete chat. Try again.'), findsOneWidget);
    expect(service.hiddenChats, isEmpty);
  });

  testWidgets('deleted chats can be found again through an explicit search', (
    tester,
  ) async {
    service.peerList = [alice];
    service.searchResults = [alice];
    service.hiddenChats.add(alice.key);
    await showHome(tester);
    expect(find.text('No conversations yet'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey(alice.key)), findsOneWidget);
    await selectDelete(tester, alice.key);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey(alice.key)), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('No conversations yet'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey(alice.key)), findsOneWidget);
  });

  testWidgets('pending preview cannot restore history after deletion', (
    tester,
  ) async {
    service.peerList = [alice];
    service.searchResults = [alice];
    final pending = Completer<List<ChatMessage>>();
    service.pendingHistory[alice.key] = pending;
    await showHome(tester);
    await selectDelete(tester, alice.key);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    pending.complete([
      _message(alice, 'Deleted preview', '2026-11-25T12:00:00Z'),
    ]);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pumpAndSettle();
    expect(find.text('Deleted preview'), findsNothing);
    expect(find.text('No messages yet'), findsOneWidget);
  });

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

  testWidgets('deleting a failed message refreshes the chat preview', (
    tester,
  ) async {
    service.peerList = [alice];
    service.history[alice.key] = _message(
      alice,
      'Failed latest message',
      '2026-11-27T12:00:00Z',
    );
    await showHome(tester);
    expect(find.text('Failed latest message'), findsOneWidget);

    service.history[alice.key] = _message(
      alice,
      'Earlier message',
      '2026-11-27T11:00:00Z',
    );
    service.messageEvents.add(MessageDeletedEvent(alice.key, 'failed'));
    await tester.pumpAndSettle();
    expect(find.text('Failed latest message'), findsNothing);
    expect(find.text('Earlier message'), findsOneWidget);

    service.history.remove(alice.key);
    service.messageEvents.add(MessageDeletedEvent(alice.key, 'earlier'));
    await tester.pumpAndSettle();
    expect(find.text('Earlier message'), findsNothing);
    expect(find.text('No messages yet'), findsOneWidget);
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
