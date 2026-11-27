import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/huginn_messenger.dart';
import 'package:huginn_messenger/main.dart';
import 'package:huginn_messenger/src/services/sticker_library.dart';
import 'package:huginn_messenger/src/widgets/sticker_picker.dart';

import 'support/memory_sticker_store.dart';

class _Messenger extends MessengerService {
  _Messenger(StickerLibrary stickers) : super(stickers: stickers);

  final messages = <ChatMessage>[];
  final sent = <String>[];
  bool sendSucceeds = true;

  @override
  Future<List<ChatMessage>> getMessagesPaginated(
    String peerId, {
    int limit = 64,
    int offset = 0,
  }) async => messages;

  @override
  bool sendMessage(String to, String text, {int ttl = 0}) {
    if (sendSucceeds) sent.add(text);
    return sendSucceeds;
  }
}

void main() {
  late StickerLibrary library;
  late _Messenger service;
  late MemoryStickerStore store;

  setUp(() {
    store = MemoryStickerStore();
    library = StickerLibrary(store: store);
    service = _Messenger(library);
  });
  tearDown(() => service.dispose());

  Future<void> showChat(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.macOS,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: ChatScreen(service: service, peerId: 'alice', peerName: 'Alice'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Stickers'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
  }

  final stickerText = find.byKey(const ValueKey('sticker-text'));
  final categoryName = find.byKey(const ValueKey('category-name'));

  Future<void> contextMenu(
    WidgetTester tester,
    Finder target,
    TargetPlatform platform,
  ) async {
    if (platform == TargetPlatform.macOS) {
      await tester.tap(target, buttons: kSecondaryMouseButton);
    } else {
      await tester.longPress(target);
    }
    await tester.pumpAndSettle();
  }

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets('context menu moves and deletes without sending on $platform', (
      tester,
    ) async {
      await showChat(tester, platform: platform);
      await openPicker(tester);
      await contextMenu(tester, find.text('(^_^)'), platform);
      expect(service.sent, isEmpty);
      await tester.tap(find.text('Переместить в папку'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Переместить'));
      await tester.pumpAndSettle();
      expect(library.categories.first.stickers, isEmpty);
      expect(library.categories.last.stickers, ['(T_T)', '(^_^)']);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);

      await contextMenu(tester, find.text('(^_^)'), platform);
      await tester.tap(find.text('Удалить стикер'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(library.categories.last.stickers, contains('(^_^)'));
      await contextMenu(tester, find.text('(^_^)'), platform);
      await tester.tap(find.text('Удалить стикер'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(library.categories.last.stickers, ['(T_T)']);

      await contextMenu(tester, find.text('Грусть'), platform);
      await tester.tap(find.text('Удалить папку'));
      await tester.pumpAndSettle();
      expect(
        find.text('Куда переместить стикеры из этой папки?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Удалить вместе со стикерами'));
      await tester.pumpAndSettle();
      expect(library.categories.single.name, 'Радость');
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
      expect(service.sent, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'folder deletion offers transfer to the selected folder on $platform',
      (tester) async {
        await library.addSticker(
          text: '(^_^)',
          categoryName: 'Другая',
          createCategory: true,
        );
        await showChat(tester, platform: platform);
        await openPicker(tester);
        await contextMenu(tester, find.text('Радость'), platform);
        await tester.tap(find.text('Удалить папку'));
        await tester.pumpAndSettle();
        final dropdown = tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>),
        );
        expect(dropdown.items!.map((item) => item.value), ['Грусть', 'Другая']);
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Другая').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Перенести и удалить папку'));
        await tester.pumpAndSettle();
        expect(library.categories.map((c) => c.name), ['Грусть', 'Другая']);
        expect(library.categories.last.stickers, ['(^_^)', '(^_^)']);
        expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
        expect(service.sent, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('folder deletion can be cancelled without changing stickers', (
    tester,
  ) async {
    await showChat(tester);
    await openPicker(tester);
    await contextMenu(tester, find.text('Радость'), TargetPlatform.macOS);
    await tester.tap(find.text('Удалить папку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(library.categories.map((c) => c.name), ['Радость', 'Грусть']);
    expect(library.categories.first.stickers, ['(^_^)']);
    expect(store.saved, isNull);
  });

  testWidgets(
    'last folder transfers into a new folder on a narrow screen and retries failures',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await library.deleteCategory('Грусть');
      await showChat(tester, platform: TargetPlatform.android);
      await openPicker(tester);
      await contextMenu(tester, find.text('Радость'), TargetPlatform.android);
      await tester.tap(find.text('Удалить папку'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Перенести и удалить папку'));
      await tester.pumpAndSettle();
      expect(find.text('Введите название категории'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      final newName = find.byKey(const ValueKey('delete-category-name'));
      await tester.enterText(newName, 'Сохранённые');
      store.failWrite = true;
      await tester.ensureVisible(find.text('Перенести и удалить папку'));
      await tester.tap(find.text('Перенести и удалить папку'));
      await tester.pumpAndSettle();
      expect(
        find.text('Не удалось сохранить изменения. Попробуйте ещё раз.'),
        findsOneWidget,
      );
      expect(library.categories.single.name, 'Радость');
      expect(library.categories.single.stickers, ['(^_^)']);
      expect(
        tester.widget<TextFormField>(newName).controller!.text,
        'Сохранённые',
      );
      store.failWrite = false;
      await tester.tap(find.text('Перенести и удалить папку'));
      await tester.pumpAndSettle();
      expect(library.categories.single.name, 'Сохранённые');
      expect(library.categories.single.stickers, ['(^_^)']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty folder can be removed without selecting a destination', (
    tester,
  ) async {
    await library.deleteSticker(categoryName: 'Радость', text: '(^_^)');
    await showChat(tester);
    await openPicker(tester);
    await contextMenu(tester, find.text('Радость'), TargetPlatform.macOS);
    await tester.tap(find.text('Удалить папку'));
    await tester.pumpAndSettle();
    expect(find.text('Папка пустая.'), findsOneWidget);
    expect(find.text('Перенести и удалить папку'), findsNothing);
    await tester.tap(find.text('Удалить папку'));
    await tester.pumpAndSettle();
    expect(library.categories.single.name, 'Грусть');
    expect(library.categories.single.stickers, ['(T_T)']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('last folder can be deleted and a new collection created', (
    tester,
  ) async {
    await library.deleteCategory('Грусть');
    await showChat(tester);
    await openPicker(tester);
    await contextMenu(tester, find.text('Радость'), TargetPlatform.macOS);
    await tester.tap(find.text('Удалить папку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить вместе со стикерами'));
    await tester.pumpAndSettle();
    expect(find.text('Пока нет стикеров'), findsOneWidget);
    expect(library.categories, isEmpty);
    await tester.tap(find.text('Создать стикер'));
    await tester.pumpAndSettle();
    await tester.enterText(stickerText, '☆');
    await tester.enterText(categoryName, 'Новая');
    await save(tester);
    expect(library.categories.single.stickers, ['☆']);
    expect(find.text('Новая'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('move into a new folder preserves draft on failure', (
    tester,
  ) async {
    await library.deleteCategory('Грусть');
    await showChat(tester);
    await openPicker(tester);
    await contextMenu(tester, find.text('(^_^)'), TargetPlatform.macOS);
    await tester.tap(find.text('Переместить в папку'));
    await tester.pumpAndSettle();
    await tester.enterText(categoryName, 'Новая');
    store.failWrite = true;
    await tester.tap(find.text('Переместить'));
    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось сохранить изменения. Попробуйте ещё раз.'),
      findsOneWidget,
    );
    expect(library.categories.single.stickers, ['(^_^)']);
    store.failWrite = false;
    await tester.tap(find.text('Переместить'));
    await tester.pumpAndSettle();
    expect(library.categories.first.stickers, isEmpty);
    expect(library.categories.last.name, 'Новая');
    expect(library.categories.last.stickers, ['(^_^)']);
    expect(service.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed folder deletion keeps dialog open for retry', (
    tester,
  ) async {
    await showChat(tester);
    await openPicker(tester);
    await contextMenu(tester, find.text('Радость'), TargetPlatform.macOS);
    await tester.tap(find.text('Удалить папку'));
    await tester.pumpAndSettle();
    store.failWrite = true;
    await tester.tap(find.text('Удалить вместе со стикерами'));
    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось сохранить изменения. Попробуйте ещё раз.'),
      findsOneWidget,
    );
    expect(library.categories.first.stickers, ['(^_^)']);
    store.failWrite = false;
    await tester.tap(find.text('Удалить вместе со стикерами'));
    await tester.pumpAndSettle();
    expect(library.categories.single.name, 'Грусть');
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'creates at the end of either category and sends exact character art',
    (tester) async {
      await showChat(tester);
      await openPicker(tester);
      await tester.tap(find.text('Грусть'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Создать стикер')).dx,
        greaterThan(tester.getTopLeft(find.text('(T_T)')).dx),
      );
      await tester.tap(find.text('Создать стикер'));
      await tester.pumpAndSettle();
      const art = '  /\\_/\\  \n ( o.o )\n  > ^ <  ';
      await tester.enterText(stickerText, art);
      await save(tester);
      expect(service.sent, isEmpty);
      expect(library.categories.last.stickers.last, art);
      expect(find.text(art), findsOneWidget);

      await tester.tap(find.text(art));
      await tester.pumpAndSettle();
      expect(service.sent, [art]);
      expect(find.byType(StickerPicker), findsNothing);

      await openPicker(tester);
      await tester.tap(find.text('Создать стикер'));
      await tester.pumpAndSettle();
      await tester.enterText(stickerText, '☆');
      await save(tester);
      expect(library.categories.first.stickers.last, '☆');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('creates an empty category and selects it immediately', (
    tester,
  ) async {
    await showChat(tester);
    await openPicker(tester);
    await tester.tap(find.byTooltip('Создать категорию'));
    await tester.pumpAndSettle();
    await tester.enterText(categoryName, 'Мои');
    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();
    expect(library.categories.last.name, 'Мои');
    expect(library.categories.last.stickers, isEmpty);
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.controller!.index, 2);
    expect(find.text('Создать стикер'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reorders categories while preserving the selected category', (
    tester,
  ) async {
    await showChat(tester);
    await openPicker(tester);
    await tester.tap(find.byTooltip('Сортировать категории'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ниже').first);
    await tester.pumpAndSettle();
    await save(tester);
    expect(library.categories.map((c) => c.name), ['Грусть', 'Радость']);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    expect(find.text('(^_^)'), findsOneWidget);

    await tester.tap(find.byTooltip('Сортировать категории'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ниже').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(library.categories.map((c) => c.name), ['Грусть', 'Радость']);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets('creates a sticker from a message on $platform', (
      tester,
    ) async {
      const body = '  (づ｡◕‿‿◕｡)づ\n  ♡  ';
      service.messages.add(
        ChatMessage(
          from: 'alice',
          text: FormattedMessageText.encodeReply(
            author: 'Bob',
            preview: 'Quote',
            body: body,
          ),
          timestamp: DateTime(2026, 11, 25),
        ),
      );
      await showChat(tester, platform: platform);
      if (platform == TargetPlatform.macOS) {
        await tester.tap(find.text(body), buttons: kSecondaryMouseButton);
      } else {
        await tester.longPress(find.text(body));
      }
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Forward'), findsOneWidget);
      await tester.tap(find.text('Создать стикер из сообщения'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(stickerText).controller!.text, body);
      await tester.tap(find.text('Создать новую категорию'));
      await tester.pumpAndSettle();
      await tester.enterText(categoryName, 'Из чата');
      await save(tester);
      expect(service.sent, isEmpty);
      expect(library.categories.last.name, 'Из чата');
      expect(library.categories.last.stickers, [body]);
      await openPicker(tester);
      await tester.tap(find.text('Из чата'));
      await tester.pumpAndSettle();
      final sticker = find.descendant(
        of: find.byType(StickerPicker),
        matching: find.text(body),
      );
      await tester.tap(sticker);
      await tester.pumpAndSettle();
      expect(service.sent, [body]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('editor allows choosing a different existing category', (
    tester,
  ) async {
    await showChat(tester);
    await openPicker(tester);
    await tester.tap(find.text('Создать стикер'));
    await tester.pumpAndSettle();
    await tester.enterText(stickerText, '♡');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Грусть').last);
    await tester.pumpAndSettle();
    await save(tester);
    expect(library.categories.last.stickers.last, '♡');
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
  });

  testWidgets('invalid input and failed writes keep the draft for retry', (
    tester,
  ) async {
    await showChat(tester);
    await openPicker(tester);
    await tester.tap(find.text('Создать стикер'));
    await tester.pumpAndSettle();
    await save(tester);
    expect(find.text('Введите символы стикера'), findsOneWidget);
    await tester.enterText(stickerText, '☆');
    await tester.tap(find.text('Создать новую категорию'));
    await tester.pumpAndSettle();
    await tester.enterText(categoryName, ' радость ');
    await save(tester);
    expect(
      find.text('Категория с таким названием уже существует'),
      findsOneWidget,
    );
    await tester.enterText(categoryName, 'Новая');
    store.failWrite = true;
    await save(tester);
    expect(
      find.text('Не удалось сохранить изменения. Попробуйте ещё раз.'),
      findsOneWidget,
    );
    expect(tester.widget<TextFormField>(stickerText).controller!.text, '☆');
    expect(library.categories, hasLength(2));
    store.failWrite = false;
    await save(tester);
    expect(library.categories.last.stickers, ['☆']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('cancelling the editor creates neither sticker nor category', (
    tester,
  ) async {
    await showChat(tester);
    await openPicker(tester);
    await tester.tap(find.text('Создать стикер'));
    await tester.pumpAndSettle();
    await tester.enterText(stickerText, '☆');
    await tester.tap(find.text('Создать новую категорию'));
    await tester.pumpAndSettle();
    await tester.enterText(categoryName, 'Отменённая');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(library.categories, hasLength(2));
    expect(store.saved, isNull);
    expect(service.sent, isEmpty);
  });

  testWidgets(
    'attachment-only messages do not offer creating an empty sticker',
    (tester) async {
      service.messages.add(
        ChatMessage(
          from: 'alice',
          text: '',
          timestamp: DateTime(2026, 11, 25),
          files: [FileMeta(fileId: 'file', filename: 'document.pdf')],
        ),
      );
      await showChat(tester);
      await tester.tap(
        find.text('document.pdf'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Создать стикер из сообщения'), findsNothing);
    },
  );

  testWidgets('narrow screen with keyboard supports multiline creation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await showChat(tester, platform: TargetPlatform.android);
    await openPicker(tester);
    await tester.tap(find.text('Создать стикер'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.enterText(
      stickerText,
      List.filled(14, '░░░░░░░░░░░░░░░░░░░').join('\n'),
    );
    await tester.ensureVisible(find.text('Создать новую категорию'));
    await tester.tap(find.text('Создать новую категорию'));
    await tester.pumpAndSettle();
    await tester.enterText(categoryName, 'Рисунки');
    await save(tester);
    expect(library.categories.last.name, 'Рисунки');
    expect(tester.takeException(), isNull);
  });
}
