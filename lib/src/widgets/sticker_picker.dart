import 'package:flutter/material.dart';

import '../models/sticker_category.dart';
import '../services/sticker_library.dart';

String _saveError(Object error) => error is StickerLibraryException
    ? error.message
    : 'Не удалось сохранить изменения. Попробуйте ещё раз.';

enum _StickerAction { move, delete }

Future<String?> showStickerEditor({
  required BuildContext context,
  required StickerLibrary library,
  String? categoryName,
  String initialText = '',
}) async {
  try {
    await library.load();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось загрузить стикеры. Попробуйте ещё раз.'),
        ),
      );
    }
    return null;
  }
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (_) => _StickerEditor(
      library: library,
      categoryName: categoryName,
      initialText: initialText,
    ),
  );
}

class StickerPicker extends StatefulWidget {
  const StickerPicker({super.key, required this.library, required this.onSend});

  final StickerLibrary library;
  final bool Function(String) onSend;

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker>
    with TickerProviderStateMixin {
  TabController? _tabs;
  List<String> _names = [];
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_libraryChanged);
    _load();
  }

  @override
  void dispose() {
    widget.library.removeListener(_libraryChanged);
    _tabs?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      await widget.library.load();
      if (!mounted) return;
      _libraryChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _libraryChanged() {
    final selected = _tabs == null || _names.isEmpty
        ? null
        : _names[_tabs!.index];
    final names = widget.library.categories
        .map((category) => category.name)
        .toList();
    if (_tabs == null ||
        names.length != _names.length ||
        names.indexed.any((entry) => entry.$2 != _names[entry.$1])) {
      _tabs?.dispose();
      final index = selected == null ? 0 : names.indexOf(selected);
      _tabs = TabController(
        length: names.length,
        initialIndex: index < 0 ? 0 : index,
        vsync: this,
      );
      _names = names;
    }
    setState(() {});
  }

  void _select(String? name) {
    if (!mounted || name == null) return;
    final index = _names.indexOf(name);
    if (index >= 0) _tabs!.animateTo(index);
  }

  Future<void> _createSticker([String? categoryName]) async {
    final selected = await showStickerEditor(
      context: context,
      library: widget.library,
      categoryName: categoryName,
    );
    _select(selected);
  }

  Future<void> _createCategory() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryEditor(library: widget.library),
    );
    _select(selected);
  }

  RelativeRect _menuPosition(Offset position) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return RelativeRect.fromRect(
      overlay.globalToLocal(position) & const Size(1, 1),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _stickerMenu(
    String category,
    String text,
    Offset position,
  ) async {
    final action = await showMenu<_StickerAction>(
      context: context,
      position: _menuPosition(position),
      items: const [
        PopupMenuItem(
          value: _StickerAction.move,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.drive_file_move_outlined),
            title: Text('Переместить в папку'),
          ),
        ),
        PopupMenuItem(
          value: _StickerAction.delete,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline),
            title: Text('Удалить стикер'),
          ),
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _StickerAction.move:
        final selected = await showDialog<String>(
          context: context,
          builder: (_) => _StickerEditor(
            library: widget.library,
            initialText: text,
            moveFromCategory: category,
          ),
        );
        _select(selected);
      case _StickerAction.delete:
        await _delete(
          title: 'Удалить стикер?',
          description: 'Стикер будет удалён из папки «$category».',
          action: () =>
              widget.library.deleteSticker(categoryName: category, text: text),
        );
      case null:
        break;
    }
  }

  Future<void> _categoryMenu(String name, Offset position) async {
    final remove = await showMenu<bool>(
      context: context,
      position: _menuPosition(position),
      items: const [
        PopupMenuItem(
          value: true,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline),
            title: Text('Удалить папку'),
          ),
        ),
      ],
    );
    if (remove != true || !mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (_) =>
          _DeleteCategoryDialog(library: widget.library, name: name),
    );
    _select(selected);
  }

  Future<void> _delete({
    required String title,
    required String description,
    required Future<void> Function() action,
  }) => showDialog<void>(
    context: context,
    builder: (_) =>
        _DeleteDialog(title: title, description: description, action: action),
  );

  Widget _grid(StickerCategory category) {
    final colorScheme = Theme.of(context).colorScheme;
    return GridView.builder(
      key: PageStorageKey(category.name),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 96,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: category.stickers.length + 1,
      itemBuilder: (_, index) {
        if (index == category.stickers.length) {
          return OutlinedButton.icon(
            onPressed: () => _createSticker(category.name),
            icon: const Icon(Icons.add),
            label: const Text('Создать стикер'),
          );
        }
        final sticker = category.stickers[index];
        return _ContextActions(
          onOpen: (position) => _stickerMenu(category.name, sticker, position),
          child: OutlinedButton(
            onPressed: () {
              if (widget.onSend(sticker)) Navigator.pop(context);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.onSurface,
              side: BorderSide(color: colorScheme.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  sticker,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: 0.65,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Не удалось загрузить стикеры'),
                  TextButton(onPressed: _load, child: const Text('Повторить')),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Стикеры',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Создать категорию',
                        icon: const Icon(Icons.create_new_folder_outlined),
                        onPressed: _createCategory,
                      ),
                      IconButton(
                        tooltip: 'Сортировать категории',
                        icon: const Icon(Icons.sort),
                        onPressed: _names.length < 2
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                builder: (_) =>
                                    _CategorySorter(library: widget.library),
                              ),
                      ),
                    ],
                  ),
                ),
                if (_names.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Пока нет стикеров'),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _createSticker,
                            icon: const Icon(Icons.add),
                            label: const Text('Создать стикер'),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabs: _names
                        .map(
                          (name) => _ContextActions(
                            onOpen: (position) => _categoryMenu(name, position),
                            child: Tab(text: name),
                          ),
                        )
                        .toList(),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: widget.library.categories.map(_grid).toList(),
                    ),
                  ),
                ],
              ],
            ),
    ),
  );
}

class _ContextActions extends StatelessWidget {
  const _ContextActions({required this.onOpen, required this.child});

  final void Function(Offset) onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onLongPressStart: (details) => onOpen(details.globalPosition),
    onSecondaryTapUp: (details) => onOpen(details.globalPosition),
    child: child,
  );
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({
    required this.title,
    required this.description,
    required this.action,
  });

  final String title;
  final String description;
  final Future<void> Function() action;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  bool _saving = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.action();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = _saveError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.description),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _delete,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(_saving ? 'Удаление…' : 'Удалить'),
        ),
      ],
    ),
  );
}

class _DeleteCategoryDialog extends StatefulWidget {
  const _DeleteCategoryDialog({required this.library, required this.name});

  final StickerLibrary library;
  final String name;

  @override
  State<_DeleteCategoryDialog> createState() => _DeleteCategoryDialogState();
}

class _DeleteCategoryDialogState extends State<_DeleteCategoryDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _hasStickers = widget.library.categories
      .firstWhere((category) => category.name == widget.name)
      .stickers
      .isNotEmpty;
  late final _destinations = widget.library.categories
      .map((category) => category.name)
      .where((name) => name != widget.name)
      .toList();
  late String? _destination = _destinations.firstOrNull;
  late bool _newCategory = _destinations.isEmpty;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _delete({required bool move}) async {
    if (move && !_form.currentState!.validate()) return;
    final destination = move
        ? (_newCategory ? _name.text.trim() : _destination!)
        : null;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.library.deleteCategory(
        widget.name,
        moveToCategory: destination,
        createCategory: move && _newCategory,
      );
      if (mounted) Navigator.pop(context, destination);
    } catch (error) {
      if (mounted) setState(() => _error = _saveError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text('Удалить папку «${widget.name}»?'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_hasStickers) ...[
                const Text('Куда переместить стикеры из этой папки?'),
                const SizedBox(height: 16),
                if (_newCategory)
                  TextFormField(
                    key: const ValueKey('delete-category-name'),
                    controller: _name,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Название новой папки',
                    ),
                    validator: (value) =>
                        widget.library.categoryNameError(value ?? ''),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _destination,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Папка назначения',
                    ),
                    items: _destinations
                        .map(
                          (name) => DropdownMenuItem(
                            value: name,
                            child: Text(name, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _destination = value),
                  ),
                if (_destinations.isNotEmpty)
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _newCategory = !_newCategory),
                    icon: Icon(
                      _newCategory ? Icons.folder_outlined : Icons.add,
                    ),
                    label: Text(
                      _newCategory
                          ? 'Выбрать существующую папку'
                          : 'Создать новую папку',
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('Можно также удалить папку вместе со стикерами.'),
              ] else
                const Text('Папка пустая.'),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        if (_hasStickers)
          TextButton(
            onPressed: _saving ? null : () => _delete(move: false),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Удалить вместе со стикерами'),
          ),
        FilledButton(
          onPressed: _saving ? null : () => _delete(move: _hasStickers),
          child: Text(
            _saving
                ? 'Сохранение…'
                : _hasStickers
                ? 'Перенести и удалить папку'
                : 'Удалить папку',
          ),
        ),
      ],
    ),
  );
}

class _StickerEditor extends StatefulWidget {
  const _StickerEditor({
    required this.library,
    this.categoryName,
    required this.initialText,
    this.moveFromCategory,
  });
  final StickerLibrary library;
  final String? categoryName;
  final String initialText;
  final String? moveFromCategory;

  @override
  State<_StickerEditor> createState() => _StickerEditorState();
}

class _StickerEditorState extends State<_StickerEditor> {
  final _form = GlobalKey<FormState>();
  late final _text = TextEditingController(text: widget.initialText);
  final _name = TextEditingController();
  late String? _category = widget.categoryName ?? _destinations.firstOrNull;
  late bool _newCategory = _destinations.isEmpty;
  bool _saving = false;
  String? _error;

  bool get _moving => widget.moveFromCategory != null;
  List<String> get _destinations => widget.library.categories
      .map((category) => category.name)
      .where((name) => name != widget.moveFromCategory)
      .toList();

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final category = _newCategory ? _name.text.trim() : _category!;
    try {
      if (_moving) {
        await widget.library.moveSticker(
          fromCategory: widget.moveFromCategory!,
          toCategory: category,
          text: widget.initialText,
          createCategory: _newCategory,
        );
      } else {
        await widget.library.addSticker(
          text: _text.text,
          categoryName: category,
          createCategory: _newCategory,
        );
      }
      if (mounted) Navigator.pop(context, category);
    } catch (error) {
      if (mounted) setState(() => _error = _saveError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(_moving ? 'Переместить стикер' : 'Создать стикер'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('sticker-text'),
                controller: _text,
                enabled: !_saving && !_moving,
                autofocus: !_moving && widget.initialText.isEmpty,
                minLines: 3,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'Символы стикера',
                  hintText: '(づ｡◕‿‿◕｡)づ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Введите символы стикера'
                    : null,
              ),
              const SizedBox(height: 16),
              if (!_newCategory)
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _moving ? 'Папка назначения' : 'Категория',
                  ),
                  items: _destinations
                      .map(
                        (name) => DropdownMenuItem(
                          value: name,
                          child: Text(name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _category = value!),
                )
              else
                TextFormField(
                  key: const ValueKey('category-name'),
                  controller: _name,
                  enabled: !_saving,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Название новой категории',
                  ),
                  validator: (value) =>
                      widget.library.categoryNameError(value ?? ''),
                ),
              if (_destinations.isNotEmpty)
                TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _newCategory = !_newCategory),
                  icon: Icon(_newCategory ? Icons.folder_outlined : Icons.add),
                  label: Text(
                    _newCategory
                        ? 'Выбрать существующую категорию'
                        : 'Создать новую категорию',
                  ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? 'Сохранение…'
                : _moving
                ? 'Переместить'
                : 'Сохранить',
          ),
        ),
      ],
    ),
  );
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({required this.library});
  final StickerLibrary library;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.library.addCategory(_name.text);
      if (mounted) Navigator.pop(context, _name.text.trim());
    } catch (error) {
      if (mounted) setState(() => _error = _saveError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Создать категорию'),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const ValueKey('category-name'),
              controller: _name,
              autofocus: true,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Название категории',
              ),
              validator: (value) =>
                  widget.library.categoryNameError(value ?? ''),
              onFieldSubmitted: (_) {
                if (!_saving) _save();
              },
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Сохранение…' : 'Создать'),
        ),
      ],
    ),
  );
}

class _CategorySorter extends StatefulWidget {
  const _CategorySorter({required this.library});
  final StickerLibrary library;

  @override
  State<_CategorySorter> createState() => _CategorySorterState();
}

class _CategorySorterState extends State<_CategorySorter> {
  late final _names = widget.library.categories
      .map((category) => category.name)
      .toList();
  bool _saving = false;
  String? _error;

  void _move(int from, int to) =>
      setState(() => _names.insert(to, _names.removeAt(from)));

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.library.reorderCategories(_names);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = _saveError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Сортировать категории'),
      content: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height * 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton.icon(
              onPressed: _saving
                  ? null
                  : () => setState(
                      () => _names.sort(
                        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                      ),
                    ),
              icon: const Icon(Icons.sort_by_alpha),
              label: const Text('По алфавиту'),
            ),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: _names.length,
                onReorderItem: (oldIndex, newIndex) {
                  if (!_saving) _move(oldIndex, newIndex);
                },
                itemBuilder: (_, index) => ListTile(
                  key: ValueKey(_names[index]),
                  contentPadding: EdgeInsets.zero,
                  leading: ReorderableDragStartListener(
                    index: index,
                    enabled: !_saving,
                    child: const Tooltip(
                      message: 'Перетащить категорию',
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                  title: Text(
                    _names[index],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Выше',
                        onPressed: _saving || index == 0
                            ? null
                            : () => _move(index, index - 1),
                        icon: const Icon(Icons.arrow_upward, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Ниже',
                        onPressed: _saving || index == _names.length - 1
                            ? null
                            : () => _move(index, index + 1),
                        icon: const Icon(Icons.arrow_downward, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Сохранение…' : 'Сохранить'),
        ),
      ],
    ),
  );
}
