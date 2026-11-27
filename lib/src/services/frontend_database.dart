import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/sticker_category.dart';

abstract interface class StickerStore {
  Future<List<StickerCategory>> load();
  Future<void> save(List<StickerCategory> categories);
}

/// Frontend-owned storage, independent of the Go core's message database.
class FrontendDatabase implements StickerStore {
  FrontendDatabase({String? path}) : _configuredPath = path;

  final String? _configuredPath;

  Future<String> _path() async =>
      _configuredPath ??
      '${(await getApplicationSupportDirectory()).path}/frontend.sqlite';

  @override
  Future<List<StickerCategory>> load() async {
    final path = await _path();
    final file = File(path);
    if (!await file.exists()) {
      final seed = await rootBundle.load('assets/frontend.sqlite');
      await file.parent.create(recursive: true);
      final temporary = File('$path.tmp');
      await temporary.writeAsBytes(
        seed.buffer.asUint8List(seed.offsetInBytes, seed.lengthInBytes),
        flush: true,
      );
      await temporary.rename(path);
    }
    // SQLite and migration I/O run off the UI isolate.
    return Isolate.run(() => _load(path));
  }

  @override
  Future<void> save(List<StickerCategory> categories) async {
    final path = await _path();
    await Isolate.run(() {
      final db = _open(path);
      try {
        _transaction(db, () => _replace(db, categories));
      } finally {
        db.close();
      }
    });
  }

  static Database _open(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readWrite);
    try {
      db.execute('PRAGMA foreign_keys = ON');
      db.execute('PRAGMA busy_timeout = 5000');
      if (db.select('PRAGMA user_version').single.values.single != 1) {
        throw const FormatException('Unsupported frontend database version');
      }
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static List<StickerCategory> _load(String path) {
    final db = _open(path);
    try {
      _transaction(db, () {
        final migrated = db.select(
          "SELECT value FROM frontend_metadata WHERE key = 'stickers_initialized'",
        );
        if (migrated.isEmpty) {
          final legacy = File('${File(path).parent.path}/stickers.json');
          if (legacy.existsSync()) {
            // The copied seed is the source of defaults. Supplement the legacy
            // collection once; never restore deletions on later launches.
            final defaults = _readCategories(db);
            final imported = _decodeLegacy(legacy.readAsStringSync());
            _replace(db, _withMissingDefaults(imported, defaults));
          }
          db.execute(
            "INSERT INTO frontend_metadata (key, value) VALUES ('stickers_initialized', '1')",
          );
        }
      });
      return _readCategories(db);
    } finally {
      db.close();
    }
  }

  static List<StickerCategory> _readCategories(Database db) {
    final stickers = <int, List<String>>{};
    for (final row in db.select(
      'SELECT category_id, text FROM stickers ORDER BY category_id, position',
    )) {
      (stickers[row['category_id'] as int] ??= []).add(row['text'] as String);
    }
    return db
        .select('SELECT id, name FROM sticker_categories ORDER BY position')
        .map(
          (row) => StickerCategory(
            name: row['name'] as String,
            stickers: stickers[row['id']] ?? const [],
          ),
        )
        .toList();
  }

  static List<StickerCategory> _withMissingDefaults(
    List<StickerCategory> imported,
    List<StickerCategory> defaults,
  ) {
    final result = List<StickerCategory>.of(imported);
    for (final category in defaults) {
      final index = result.indexWhere(
        (existing) =>
            existing.name.toLowerCase() == category.name.toLowerCase(),
      );
      if (index < 0) {
        result.add(category);
        continue;
      }
      final existing = result[index];
      final stickers = List<String>.of(existing.stickers);
      // Account for existing occurrences so a complete legacy export is not
      // duplicated, while repeated stickers in either collection are retained.
      final available = <String, int>{};
      for (final text in stickers) {
        available[text] = (available[text] ?? 0) + 1;
      }
      for (final text in category.stickers) {
        final count = available[text] ?? 0;
        if (count > 0) {
          available[text] = count - 1;
        } else {
          stickers.add(text);
        }
      }
      result[index] = StickerCategory(name: existing.name, stickers: stickers);
    }
    return result;
  }

  static List<StickerCategory> _decodeLegacy(String data) {
    final json = jsonDecode(data);
    if (json is! Map<String, dynamic> ||
        json['version'] != 1 ||
        json['categories'] is! List) {
      throw const FormatException('Invalid sticker library');
    }
    final categories = <StickerCategory>[];
    final names = <String>{};
    for (final value in json['categories'] as List) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid sticker category');
      }
      final category = StickerCategory.fromJson(value);
      if (!names.add(category.name.toLowerCase())) {
        throw const FormatException('Duplicate sticker category');
      }
      categories.add(category);
    }
    return categories;
  }

  static void _replace(Database db, List<StickerCategory> categories) {
    db.execute('DELETE FROM sticker_categories');
    final categoryInsert = db.prepare(
      'INSERT INTO sticker_categories (name, position) VALUES (?, ?)',
    );
    final stickerInsert = db.prepare(
      'INSERT INTO stickers (category_id, text, position) VALUES (?, ?, ?)',
    );
    try {
      for (final (position, category) in categories.indexed) {
        categoryInsert.execute([category.name, position]);
        final id = db.lastInsertRowId;
        for (final (index, text) in category.stickers.indexed) {
          stickerInsert.execute([id, text, index]);
        }
      }
    } finally {
      categoryInsert.close();
      stickerInsert.close();
    }
  }

  static void _transaction(Database db, void Function() action) {
    db.execute('BEGIN IMMEDIATE');
    try {
      action();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}
