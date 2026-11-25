import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/src/services/sticker_library.dart';

void main() {
  late StickerLibrary library;
  String? saved;
  bool failWrite = false;
  const defaults = {
    'Радость': ['(^_^)'],
    'Грусть': ['(T_T)'],
  };

  setUp(() {
    saved = null;
    failWrite = false;
    library = StickerLibrary(
      defaults: defaults,
      read: () async => saved,
      write: (data) async {
        if (failWrite) throw StateError('disk full');
        saved = data;
      },
    );
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

    final reopened = StickerLibrary(
      read: () async => saved,
      write: (_) async {},
    );
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
      failWrite = true;
      await expectLater(
        library.addSticker(
          text: '☆',
          categoryName: 'Новая',
          createCategory: true,
        ),
        throwsStateError,
      );
      expect(library.categories, hasLength(2));
      expect(saved, isNull);
      failWrite = false;
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
      expect(saved, isNull);
      // The same sticker may intentionally belong to different categories.
      await library.addSticker(text: '(^_^)', categoryName: 'Грусть');
      expect(library.categories.last.stickers, ['(T_T)', '(^_^)']);
    },
  );

  test('overlapping writes retain both additions in order', () async {
    final gate = Completer<void>();
    var writes = 0;
    final queued = StickerLibrary(
      defaults: defaults,
      read: () async => null,
      write: (data) async {
        if (++writes == 1) await gate.future;
        saved = data;
      },
    );
    addTearDown(queued.dispose);
    final first = queued.addSticker(text: '1', categoryName: 'Радость');
    final second = queued.addSticker(text: '2', categoryName: 'Радость');
    gate.complete();
    await Future.wait([first, second]);
    expect(queued.categories.first.stickers, ['(^_^)', '1', '2']);
    expect((jsonDecode(saved!)['categories'] as List).first['stickers'], [
      '(^_^)',
      '1',
      '2',
    ]);
  });

  test('unreadable saved data is not overwritten and can be retried', () async {
    saved = '{broken';
    await expectLater(library.load(), throwsFormatException);
    await expectLater(library.addCategory('Мои'), throwsFormatException);
    expect(saved, '{broken');
    saved = null;
    await library.load();
    await library.addCategory('Мои');
    expect(library.categories.last.name, 'Мои');
  });

  test('invalid saved schema is rejected without replacing defaults', () async {
    for (final categories in [
      [],
      [
        {'name': '', 'stickers': []},
      ],
      [
        {
          'name': 'Мои',
          'stickers': [42],
        },
      ],
      [
        {'name': 'Мои', 'stickers': []},
        {'name': 'мои', 'stickers': []},
      ],
    ]) {
      saved = jsonEncode({'version': 1, 'categories': categories});
      await expectLater(library.load(), throwsFormatException);
      expect(library.categories.map((c) => c.name), defaults.keys);
    }
  });
}
