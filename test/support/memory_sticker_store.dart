import 'package:huginn_messenger/src/models/sticker_category.dart';
import 'package:huginn_messenger/src/services/frontend_database.dart';

class MemoryStickerStore implements StickerStore {
  MemoryStickerStore({
    Map<String, List<String>> defaults = const {
      'Радость': ['(^_^)'],
      'Грусть': ['(T_T)'],
    },
  }) : initial = defaults.entries
           .map((e) => StickerCategory(name: e.key, stickers: e.value))
           .toList();

  final List<StickerCategory> initial;
  List<StickerCategory>? saved;
  bool failWrite = false;
  bool failRead = false;
  Future<void> Function()? beforeSave;

  @override
  Future<List<StickerCategory>> load() async {
    if (failRead) throw StateError('read failed');
    return saved ?? initial;
  }

  @override
  Future<void> save(List<StickerCategory> categories) async {
    await beforeSave?.call();
    if (failWrite) throw StateError('disk full');
    saved = List.of(categories);
  }
}
