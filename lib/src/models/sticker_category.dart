class StickerCategory {
  StickerCategory({required this.name, required Iterable<String> stickers})
    : stickers = List.unmodifiable(stickers);

  final String name;
  final List<String> stickers;

  factory StickerCategory.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final stickers = json['stickers'];
    if (name is! String ||
        name.trim().isEmpty ||
        stickers is! List ||
        stickers.any((text) => text is! String || text.trim().isEmpty)) {
      throw const FormatException('Invalid sticker category');
    }
    return StickerCategory(
      name: name.trim(),
      stickers: stickers.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'stickers': stickers};
}
