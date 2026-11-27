import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/src/services/frontend_database.dart';
import 'package:huginn_messenger/src/services/sticker_library.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String path;
  late StickerLibrary library;

  StickerLibrary open() => StickerLibrary(store: FrontendDatabase(path: path));

  List<Map<String, dynamic>> defaults() {
    final db = sqlite3.open('assets/frontend.sqlite', mode: OpenMode.readOnly);
    try {
      return [
        for (final row in db.select(
          'SELECT id, name FROM sticker_categories ORDER BY position',
        ))
          {
            'name': row['name'],
            'stickers': db
                .select(
                  'SELECT text FROM stickers WHERE category_id = ? ORDER BY position',
                  [row['id']],
                )
                .map((sticker) => sticker['text'] as String)
                .toList(),
          },
      ];
    } finally {
      db.close();
    }
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('huginn-stickers-');
    path = '${directory.path}/frontend.sqlite';
    library = open();
  });
  tearDown(() async {
    library.dispose();
    await directory.delete(recursive: true);
  });

  test('bundled database contains every original sticker and folder', () async {
    await library.load();
    expect(library.categories, hasLength(11));
    expect(library.categories.expand((c) => c.stickers), hasLength(295));
    expect(library.categories.first.name, 'Радость');
    expect(library.categories.last.stickers.single, startsWith('ЗАПУСКАЕМ\n'));
    expect(library.categories[9].stickers, contains('¯\\_(ツ)_/¯'));
    final db = sqlite3.open(path);
    try {
      expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      expect(db.select('SELECT * FROM stickers'), hasLength(295));
    } finally {
      db.close();
    }
  });

  test(
    'custom-only legacy collection gains defaults once and keeps custom content',
    () async {
      const art = '  /\\_/\\  \n ( o.o )\n  > ^ <  ';
      final categories = [
        {
          'name': 'Мои',
          'stickers': [art, '♡', '♡'],
        },
        {'name': 'Пустая', 'stickers': <String>[]},
        {
          'name': 'Другие',
          'stickers': ['☆'],
        },
      ];
      final legacy = File('${directory.path}/stickers.json');
      final original = jsonEncode({'version': 1, 'categories': categories});
      await legacy.writeAsString(original);
      await library.load();
      expect(library.categories.map((c) => c.toJson()), [
        ...categories,
        ...defaults(),
      ]);
      await library.moveSticker(
        fromCategory: 'Мои',
        toCategory: 'Пустая',
        text: art,
      );
      await library.deleteSticker(categoryName: 'Мои', text: '♡');
      await library.deleteCategory('Другие');
      await library.deleteCategory('Радость');
      final order = [
        'Пустая',
        'Мои',
        ...library.categories.skip(2).map((c) => c.name),
      ];
      await library.reorderCategories(order);
      final reopened = open();
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.categories.map((c) => c.name), order);
      expect(reopened.categories.first.stickers, [art]);
      expect(reopened.categories[1].stickers, ['♡']);
      expect(await legacy.readAsString(), original);
    },
  );

  test('complete legacy defaults are not duplicated or reordered', () async {
    final categories = defaults().reversed.toList();
    (categories.first['stickers'] as List<String>).add(
      '  пользовательский\n  ',
    );
    await File(
      '${directory.path}/stickers.json',
    ).writeAsString(jsonEncode({'version': 1, 'categories': categories}));
    await library.load();
    expect(library.categories.map((c) => c.toJson()), categories);
    final reopened = open();
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.categories.map((c) => c.toJson()), categories);
  });

  test(
    'partial legacy defaults are filled without replacing custom stickers',
    () async {
      final seed = defaults();
      final joy = seed.first['stickers'] as List<String>;
      final love = seed[1]['stickers'] as List<String>;
      final custom = '  мой стикер\n  ☆  ';
      final categories = [
        {
          'name': 'радость',
          'stickers': [custom, joy[1], joy[0], joy[0]],
        },
        {
          'name': 'Любовь',
          'stickers': ['♡'],
        },
        {'name': 'Моя пустая папка', 'stickers': <String>[]},
      ];
      await File(
        '${directory.path}/stickers.json',
      ).writeAsString(jsonEncode({'version': 1, 'categories': categories}));
      await library.load();
      expect(library.categories, hasLength(12));
      expect(library.categories.first.name, 'радость');
      expect(library.categories.first.stickers.take(4), [
        custom,
        joy[1],
        joy[0],
        joy[0],
      ]);
      expect(library.categories.first.stickers, containsAll(joy));
      expect(library.categories.first.stickers, hasLength(joy.length + 2));
      expect(library.categories[1].stickers, hasLength(love.length));
      expect(
        library.categories[1].stickers.where((text) => text == '♡'),
        hasLength(love.where((text) => text == '♡').length),
      );
      expect(library.categories[2].stickers, isEmpty);
      expect(library.categories.skip(3).map((c) => c.toJson()), seed.skip(2));
      await library.deleteSticker(categoryName: 'радость', text: joy[1]);
      final reopened = open();
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.categories.first.stickers, isNot(contains(joy[1])));
    },
  );

  test(
    'empty collection stays empty after restart and can be reused',
    () async {
      await library.load();
      for (final category in List.of(library.categories)) {
        await library.deleteCategory(category.name);
      }
      final reopened = open();
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.categories, isEmpty);
      await reopened.addSticker(
        text: '☆',
        categoryName: 'Новая',
        createCategory: true,
      );
      final another = open();
      addTearDown(another.dispose);
      await another.load();
      expect(another.categories.single.stickers, ['☆']);
      final db = sqlite3.open(path);
      try {
        expect(db.select('SELECT * FROM stickers'), hasLength(1));
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
    },
  );

  test(
    'failed database transaction preserves source, destination and order',
    () async {
      await library.load();
      await library.addCategory('Назначение');
      final original = library.categories.map((c) => c.toJson()).toList();
      final text = library.categories.first.stickers.first;
      final db = sqlite3.open(path);
      db.execute('''
      CREATE TRIGGER fail_write BEFORE INSERT ON stickers
      BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END
    ''');
      db.close();
      await expectLater(
        library.moveSticker(
          fromCategory: 'Радость',
          toCategory: 'Назначение',
          text: text,
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(library.categories.map((c) => c.toJson()), original);
      final reopened = open();
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.categories.map((c) => c.toJson()), original);
      final retryDb = sqlite3.open(path);
      retryDb.execute('DROP TRIGGER fail_write');
      retryDb.close();
      await library.moveSticker(
        fromCategory: 'Радость',
        toCategory: 'Назначение',
        text: text,
      );
      expect(library.categories.first.stickers, isNot(contains(text)));
      expect(library.categories.last.stickers, [text]);
    },
  );

  test(
    'folder transfer rolls back on failure and preserves all copies after restart',
    () async {
      const art = '  рисунок\n  ♡  ';
      final categories = [
        {
          'name': 'Источник',
          'stickers': [art, '♡', '♡'],
        },
        {
          'name': 'Назначение',
          'stickers': ['♡'],
        },
      ];
      await File(
        '${directory.path}/stickers.json',
      ).writeAsString(jsonEncode({'version': 1, 'categories': categories}));
      await library.load();
      final expected = [...categories, ...defaults()];
      final db = sqlite3.open(path);
      db.execute('''
      CREATE TRIGGER fail_transfer BEFORE INSERT ON stickers
      BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END
    ''');
      db.close();
      await expectLater(
        library.deleteCategory('Источник', moveToCategory: 'Назначение'),
        throwsA(isA<SqliteException>()),
      );
      expect(library.categories.map((c) => c.toJson()), expected);
      final failed = open();
      addTearDown(failed.dispose);
      await failed.load();
      expect(failed.categories.map((c) => c.toJson()), expected);
      final retryDb = sqlite3.open(path);
      retryDb.execute('DROP TRIGGER fail_transfer');
      retryDb.close();
      await library.deleteCategory('Источник', moveToCategory: 'Назначение');
      final reopened = open();
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.categories.first.name, 'Назначение');
      expect(reopened.categories.first.stickers, ['♡', art, '♡', '♡']);
      await reopened.deleteCategory(
        'Назначение',
        moveToCategory: 'Новая',
        createCategory: true,
      );
      final movedAgain = open();
      addTearDown(movedAgain.dispose);
      await movedAgain.load();
      expect(movedAgain.categories.last.name, 'Новая');
      expect(movedAgain.categories.last.stickers, ['♡', art, '♡', '♡']);
    },
  );

  for (final invalid in [
    '{broken',
    '{"version":2,"categories":[]}',
    '{"version":1,"categories":[{"name":"","stickers":[]}]}',
    '{"version":1,"categories":[{"name":"Мои","stickers":[42]}]}',
    '{"version":1,"categories":[{"name":"Мои","stickers":[]},{"name":"мои","stickers":[]}]}',
  ]) {
    test(
      'invalid legacy data is preserved and migration can retry: $invalid',
      () async {
        final legacy = File('${directory.path}/stickers.json');
        await legacy.writeAsString(invalid);
        await expectLater(library.load(), throwsFormatException);
        await expectLater(library.addCategory('Новая'), throwsFormatException);
        expect(await legacy.readAsString(), invalid);
        final db = sqlite3.open(path);
        try {
          expect(db.select('SELECT * FROM stickers'), hasLength(295));
          expect(db.select('SELECT * FROM frontend_metadata'), isEmpty);
        } finally {
          db.close();
        }
        await legacy.writeAsString('{"version":1,"categories":[]}');
        await library.load();
        expect(library.categories.map((c) => c.toJson()), defaults());
      },
    );
  }

  test(
    'unsupported database version is never replaced with defaults',
    () async {
      await library.load();
      final db = sqlite3.open(path);
      db.execute('PRAGMA user_version = 99');
      db.close();
      final reopened = open();
      addTearDown(reopened.dispose);
      await expectLater(reopened.load(), throwsFormatException);
      final check = sqlite3.open(path);
      try {
        expect(check.select('PRAGMA user_version').single.values.single, 99);
        expect(check.select('SELECT * FROM stickers'), hasLength(295));
      } finally {
        check.close();
      }
    },
  );
}
