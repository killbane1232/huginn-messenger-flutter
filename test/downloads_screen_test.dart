import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/main.dart';
import 'package:huginn_messenger/src/models/file_download.dart';
import 'package:huginn_messenger/src/services/messenger_service.dart';
import 'package:huginn_messenger/src/widgets/downloads_screen.dart';

class _DownloadsService extends MessengerService {
  List<FileDownload> downloads = [];
  final cancelled = <String>[];
  bool failLoad = false;
  bool failCancel = false;
  int reads = 0;
  Completer<List<FileDownload>>? pendingRead;

  @override
  Future<List<FileDownload>> getFileDownloads() async {
    reads++;
    final pending = pendingRead;
    pendingRead = null;
    if (pending != null) return pending.future;
    if (failLoad) throw StateError('load failed');
    return List.of(downloads);
  }

  @override
  Future<void> cancelFileDownload(String fileId) async {
    if (failCancel) throw StateError('cancel failed');
    cancelled.add(fileId);
    downloads.removeWhere((item) => item.fileId == fileId);
  }
}

FileDownload _download(String id, int received) => FileDownload(
  fileId: id,
  filename: '$id.txt',
  receivedChunks: received,
  totalChunks: 4,
);

void main() {
  late _DownloadsService service;
  setUp(() => service = _DownloadsService());
  tearDown(() => service.dispose());

  Future<void> showDownloads(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DownloadsScreen(service: service)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows all downloads, updates progress and cancels selected file',
    (tester) async {
      service.downloads = [_download('first', 1), _download('second', 2)];
      await showDownloads(tester);
      expect(find.text('first.txt'), findsOneWidget);
      expect(find.text('second.txt'), findsOneWidget);
      expect(find.text('25% · 1 / 4 parts received'), findsOneWidget);
      expect(find.text('50% · 2 / 4 parts received'), findsOneWidget);
      expect(
        tester
            .widgetList<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .map((widget) => widget.value),
        [0.25, 0.5],
      );
      service.downloads[0] = _download('first', 3);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('75% · 3 / 4 parts received'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel download').first);
      await tester.pumpAndSettle();
      expect(service.cancelled, ['first']);
      expect(find.text('first.txt'), findsNothing);
      expect(find.text('second.txt'), findsOneWidget);

      service.downloads.clear();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('No downloads in progress'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      final reads = service.reads;
      await tester.pump(const Duration(seconds: 3));
      expect(service.reads, reads);
    },
  );

  testWidgets(
    'shows errors, keeps active rows on failed cancellation and retries',
    (tester) async {
      service.failLoad = true;
      await showDownloads(tester);
      expect(find.text('Could not load downloads.'), findsOneWidget);
      expect(find.text('No downloads in progress'), findsNothing);
      service.failLoad = false;
      service.downloads = [_download('first', 4)];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('100% · Finishing…'), findsOneWidget);
      service.failCancel = true;
      await tester.tap(find.byTooltip('Cancel download'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not cancel download. Try again.'),
        findsOneWidget,
      );
      expect(find.text('first.txt'), findsOneWidget);
      expect(service.cancelled, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a stale refresh cannot restore a cancelled row', (tester) async {
    service.downloads = [_download('first', 1)];
    await showDownloads(tester);
    final stale = Completer<List<FileDownload>>();
    service.pendingRead = stale;
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Cancel download'));
    await tester.pumpAndSettle();
    stale.complete([_download('first', 1)]);
    await tester.pump();
    expect(find.text('No downloads in progress'), findsOneWidget);
    expect(find.text('first.txt'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final chat in [false, true]) {
    testWidgets(
      'downloads button opens the list from ${chat ? 'chat' : 'home'}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: chat
                ? ChatScreen(service: service, peerId: 'peer', peerName: 'Peer')
                : HomeScreen(service: service),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Downloads'));
        await tester.pumpAndSettle();
        expect(find.byType(DownloadsScreen), findsOneWidget);
        expect(find.text('No downloads in progress'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(DownloadsScreen), findsNothing);
      },
    );
  }
}
