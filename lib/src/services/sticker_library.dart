import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/default_stickers.dart';
import '../models/sticker_category.dart';

class StickerLibraryException implements Exception {
  const StickerLibraryException(this.message);
  final String message;
}

/// One library shared by all chats. Changes become visible only after saving.
class StickerLibrary extends ChangeNotifier {
  StickerLibrary({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
    Map<String, List<String>> defaults = defaultStickerCategories,
  }) : _read = read ?? _readFile,
       _write = write ?? _writeFile,
       _categories = List.unmodifiable(
         defaults.entries.map(
           (entry) => StickerCategory(name: entry.key, stickers: entry.value),
         ),
       );

  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  List<StickerCategory> _categories;
  Future<void>? _loading;
  Future<void>? _pending;
  bool _disposed = false;

  List<StickerCategory> get categories => _categories;

  static Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/stickers.json');
  }

  static Future<String?> _readFile() async {
    final file = await _file();
    return await file.exists() ? file.readAsString() : null;
  }

  static Future<void> _writeFile(String data) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(data, flush: true);
    await temporary.rename(file.path);
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final data = await Future<String?>.sync(_read);
      if (data != null) {
        final json = jsonDecode(data) as Map<String, dynamic>;
        if (json['version'] != 1) {
          throw const FormatException('Unsupported sticker library version');
        }
        final categories = (json['categories'] as List)
            .map(
              (value) =>
                  StickerCategory.fromJson(value as Map<String, dynamic>),
            )
            .toList();
        final names = categories.map((category) => category.name.toLowerCase());
        if (categories.isEmpty || names.toSet().length != categories.length) {
          throw const FormatException('Invalid sticker categories');
        }
        _categories = List.unmodifiable(categories);
      }
      if (!_disposed) notifyListeners();
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  String? categoryNameError(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) return 'Введите название категории';
    if (_categories.any(
      (category) => category.name.toLowerCase() == normalized.toLowerCase(),
    )) {
      return 'Категория с таким названием уже существует';
    }
    return null;
  }

  void _validateNewCategory(String name) {
    final error = categoryNameError(name);
    if (error != null) throw StickerLibraryException(error);
  }

  Future<void> addCategory(String name) => _update((categories) {
    _validateNewCategory(name);
    categories.add(StickerCategory(name: name.trim(), stickers: const []));
  });

  Future<void> addSticker({
    required String text,
    required String categoryName,
    bool createCategory = false,
  }) => _update((categories) {
    if (text.trim().isEmpty) {
      throw const StickerLibraryException('Введите символы стикера');
    }
    final name = categoryName.trim();
    if (createCategory) {
      _validateNewCategory(name);
      categories.add(StickerCategory(name: name, stickers: [text]));
      return;
    }
    final index = categories.indexWhere((category) => category.name == name);
    if (index < 0) {
      throw const StickerLibraryException('Выберите категорию');
    }
    final category = categories[index];
    if (category.stickers.contains(text)) {
      throw const StickerLibraryException('Этот стикер уже есть в категории');
    }
    // Preserve spacing and newlines: they can be part of the character art.
    categories[index] = StickerCategory(
      name: name,
      stickers: [...category.stickers, text],
    );
  });

  Future<void> reorderCategories(List<String> names) => _update((categories) {
    final byName = {for (final category in categories) category.name: category};
    if (names.length != categories.length ||
        names.toSet().length != categories.length ||
        !names.every(byName.containsKey)) {
      throw const StickerLibraryException(
        'Список категорий изменился. Повторите сортировку.',
      );
    }
    categories
      ..clear()
      ..addAll(names.map((name) => byName[name]!));
  });

  Future<void> _update(void Function(List<StickerCategory>) change) {
    final operation = (_pending ?? Future<void>.value()).then((_) async {
      await load();
      final next = List<StickerCategory>.of(_categories);
      change(next);
      await _write(
        jsonEncode({
          'version': 1,
          'categories': next.map((category) => category.toJson()).toList(),
        }),
      );
      _categories = List.unmodifiable(next);
      if (!_disposed) notifyListeners();
    });
    // A failed save must not prevent retries or subsequent changes.
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
