import 'package:flutter/foundation.dart';

import '../models/sticker_category.dart';
import 'frontend_database.dart';

class StickerLibraryException implements Exception {
  const StickerLibraryException(this.message);
  final String message;
}

/// One library shared by all chats. Changes become visible only after saving.
class StickerLibrary extends ChangeNotifier {
  StickerLibrary({StickerStore? store}) : _store = store ?? FrontendDatabase();

  final StickerStore _store;
  List<StickerCategory> _categories = const [];
  Future<void>? _loading;
  Future<void>? _pending;
  bool _disposed = false;

  List<StickerCategory> get categories => _categories;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      _categories = List.unmodifiable(await _store.load());
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

  Future<void> deleteCategory(
    String name, {
    String? moveToCategory,
    bool createCategory = false,
  }) => _update((categories) {
    final source = _categoryIndex(categories, name);
    if (moveToCategory != null) {
      final destinationName = moveToCategory.trim();
      final stickers = categories[source].stickers;
      if (createCategory) {
        _validateNewCategory(destinationName);
        categories.add(
          StickerCategory(name: destinationName, stickers: stickers),
        );
      } else {
        final destination = _categoryIndex(categories, destinationName);
        if (source == destination) {
          throw const StickerLibraryException('Выберите другую папку');
        }
        final target = categories[destination];
        // Keep every occurrence, including duplicates, when removing a folder.
        categories[destination] = StickerCategory(
          name: target.name,
          stickers: [...target.stickers, ...stickers],
        );
      }
    } else if (createCategory) {
      throw const StickerLibraryException('Введите название папки');
    }
    // Transfer and removal are committed together by _update.
    categories.removeAt(source);
  });

  Future<void> deleteSticker({
    required String categoryName,
    required String text,
  }) => _update((categories) {
    final index = _categoryIndex(categories, categoryName);
    categories[index] = _withoutSticker(categories[index], text);
  });

  Future<void> moveSticker({
    required String fromCategory,
    required String toCategory,
    required String text,
    bool createCategory = false,
  }) => _update((categories) {
    final source = _categoryIndex(categories, fromCategory);
    final updated = _withoutSticker(categories[source], text);
    final destinationName = toCategory.trim();
    if (createCategory) {
      _validateNewCategory(destinationName);
      categories.add(StickerCategory(name: destinationName, stickers: [text]));
    } else {
      final destination = _categoryIndex(categories, destinationName);
      if (source == destination) {
        throw const StickerLibraryException('Выберите другую папку');
      }
      final target = categories[destination];
      if (target.stickers.contains(text)) {
        throw const StickerLibraryException('Этот стикер уже есть в папке');
      }
      categories[destination] = StickerCategory(
        name: target.name,
        stickers: [...target.stickers, text],
      );
    }
    categories[source] = updated;
  });

  static int _categoryIndex(List<StickerCategory> categories, String name) {
    final index = categories.indexWhere((category) => category.name == name);
    if (index < 0) {
      throw const StickerLibraryException('Папка уже удалена');
    }
    return index;
  }

  static StickerCategory _withoutSticker(
    StickerCategory category,
    String text,
  ) {
    final stickers = List<String>.of(category.stickers);
    // Older collections can contain identical stickers; remove one occurrence.
    if (!stickers.remove(text)) {
      throw const StickerLibraryException('Стикер уже перемещён или удалён');
    }
    return StickerCategory(name: category.name, stickers: stickers);
  }

  Future<void> _update(void Function(List<StickerCategory>) change) {
    final operation = (_pending ?? Future<void>.value()).then((_) async {
      await load();
      final next = List<StickerCategory>.of(_categories);
      change(next);
      await _store.save(next);
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
