import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/src/services/sticker_library.dart';

import 'support/memory_sticker_store.dart';

void main() {
  late StickerLibrary library;
  late MemoryStickerStore store;

  setUp(() {
    store = MemoryStickerStore();
    library = StickerLibrary(store: store);
  });
  tearDown(() => library.dispose());

  test('custom stickers, empty categories and order survive reload', () async {
    const art = '  /\\_/\\  \n ( o.o )\n  > ^ <  ';
    await library.load();
    await library.addSticker(text: art, categoryName: 'Радость');
    await library.addCategory('  Пустая  ');
    await library.addSticker(
      text: '♡',
      categoryName: 'Мои',
      createCategory: true,
    );
    await library.reorderCategories(['Мои', 'Грусть', 'Пустая', 'Радость']);

    final reopened = StickerLibrary(store: store);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.categories.map((c) => c.name), [
      'Мои',
      'Грусть',
      'Пустая',
      'Радость',
    ]);
    expect(reopened.categories.first.stickers, ['♡']);
    expect(reopened.categories[2].stickers, isEmpty);
    expect(reopened.categories.last.stickers, ['(^_^)', art]);
  });

  test(
    'failed save commits neither new category nor sticker; retry succeeds',
    () async {
      await library.load();
      store.failWrite = true;
      await expectLater(
        library.addSticker(
          text: '☆',
          categoryName: 'Новая',
          createCategory: true,
        ),
        throwsStateError,
      );
      expect(library.categories, hasLength(2));
      expect(store.saved, isNull);
      store.failWrite = false;
      await library.addSticker(
        text: '☆',
        categoryName: 'Новая',
        createCategory: true,
      );
      expect(library.categories.last.stickers, ['☆']);
    },
  );

  test(
    'rejects empty content, duplicate categories and duplicate stickers',
    () async {
      await library.load();
      final invalid = [
        () => library.addCategory(' \n '),
        () => library.addCategory(' радость '),
        () => library.addSticker(text: ' \n ', categoryName: 'Радость'),
        () => library.addSticker(text: '(^_^)', categoryName: 'Радость'),
        () => library.addSticker(text: '☆', categoryName: 'Нет'),
        () => library.addSticker(
          text: '☆',
          categoryName: 'Грусть',
          createCategory: true,
        ),
        () => library.reorderCategories(['Радость', 'Радость']),
      ];
      for (final operation in invalid) {
        await expectLater(operation(), throwsA(isA<StickerLibraryException>()));
      }
      expect(store.saved, isNull);
      // The same sticker may intentionally belong to different categories.
      await library.addSticker(text: '(^_^)', categoryName: 'Грусть');
      expect(library.categories.last.stickers, ['(T_T)', '(^_^)']);
    },
  );

  test('overlapping writes retain both additions in order', () async {
    final gate = Completer<void>();
    var writes = 0;
    store.beforeSave = () async {
      if (++writes == 1) await gate.future;
    };
    final queued = StickerLibrary(store: store);
    addTearDown(queued.dispose);
    final first = queued.addSticker(text: '1', categoryName: 'Радость');
    final second = queued.addSticker(text: '2', categoryName: 'Радость');
    gate.complete();
    await Future.wait([first, second]);
    expect(queued.categories.first.stickers, ['(^_^)', '1', '2']);
    expect(store.saved!.first.stickers, ['(^_^)', '1', '2']);
  });

  test(
    'deleting a folder transfers every sticker, including duplicates',
    () async {
      await library.addSticker(text: '(T_T)', categoryName: 'Радость');
      await library.deleteCategory('Грусть', moveToCategory: 'Радость');
      expect(library.categories.single.name, 'Радость');
      expect(library.categories.single.stickers, ['(^_^)', '(T_T)', '(T_T)']);
      final reopened = StickerLibrary(store: store);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.categories.single.stickers, ['(^_^)', '(T_T)', '(T_T)']);
    },
  );

  test(
    'invalid transfer or failed save never deletes the source folder',
    () async {
      await library.load();
      for (final action in [
        () => library.deleteCategory('Радость', moveToCategory: 'Радость'),
        () => library.deleteCategory('Радость', moveToCategory: 'Нет'),
        () => library.deleteCategory('Нет', moveToCategory: 'Грусть'),
        () => library.deleteCategory(
          'Радость',
          moveToCategory: ' грусть ',
          createCategory: true,
        ),
        () => library.deleteCategory(
          'Радость',
          moveToCategory: ' ',
          createCategory: true,
        ),
        () => library.deleteCategory('Радость', createCategory: true),
      ]) {
        await expectLater(action(), throwsA(isA<StickerLibraryException>()));
      }
      expect(store.saved, isNull);
      store.failWrite = true;
      await expectLater(
        library.deleteCategory(
          'Радость',
          moveToCategory: 'Новая',
          createCategory: true,
        ),
        throwsStateError,
      );
      expect(library.categories.map((c) => c.name), ['Радость', 'Грусть']);
      expect(library.categories.first.stickers, ['(^_^)']);
      store.failWrite = false;
      await library.deleteCategory(
        'Радость',
        moveToCategory: 'Новая',
        createCategory: true,
      );
      expect(library.categories.map((c) => c.name), ['Грусть', 'Новая']);
      expect(library.categories.last.stickers, ['(^_^)']);
    },
  );

  test(
    'moves and deletes are atomic and reject stale or duplicate targets',
    () async {
      await library.load();
      await library.addSticker(text: '(^_^)', categoryName: 'Грусть');
      await expectLater(
        library.moveSticker(
          fromCategory: 'Радость',
          toCategory: 'Грусть',
          text: '(^_^)',
        ),
        throwsA(isA<StickerLibraryException>()),
      );
      expect(library.categories.first.stickers, ['(^_^)']);
      await library.deleteSticker(categoryName: 'Грусть', text: '(^_^)');
      store.failWrite = true;
      await expectLater(library.deleteCategory('Радость'), throwsStateError);
      await expectLater(
        library.deleteSticker(categoryName: 'Радость', text: '(^_^)'),
        throwsStateError,
      );
      await expectLater(
        library.moveSticker(
          fromCategory: 'Радость',
          toCategory: 'Новая',
          text: '(^_^)',
          createCategory: true,
        ),
        throwsStateError,
      );
      expect(library.categories, hasLength(2));
      expect(library.categories.first.stickers, ['(^_^)']);
      store.failWrite = false;
      await library.moveSticker(
        fromCategory: 'Радость',
        toCategory: 'Новая',
        text: '(^_^)',
        createCategory: true,
      );
      expect(library.categories.first.stickers, isEmpty);
      expect(library.categories.last.stickers, ['(^_^)']);
      for (final action in [
        () => library.deleteSticker(categoryName: 'Радость', text: '(^_^)'),
        () => library.deleteCategory('Нет'),
        () => library.moveSticker(
          fromCategory: 'Новая',
          toCategory: 'Нет',
          text: '(^_^)',
        ),
        () => library.moveSticker(
          fromCategory: 'Новая',
          toCategory: 'Новая',
          text: '(^_^)',
        ),
      ]) {
        await expectLater(action(), throwsA(isA<StickerLibraryException>()));
      }
      expect(library.categories.last.stickers, ['(^_^)']);
    },
  );

  test(
    'failed load can be retried without overwriting the collection',
    () async {
      store.failRead = true;
      await expectLater(library.load(), throwsStateError);
      await expectLater(library.addCategory('Мои'), throwsStateError);
      expect(store.saved, isNull);
      store.failRead = false;
      await library.addCategory('Мои');
      expect(library.categories.last.name, 'Мои');
    },
  );
}
