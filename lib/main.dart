import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'huginn_messenger.dart';
import 'src/services/platform_service.dart';
import 'src/services/notification_service.dart';

void main() {
  runApp(const HuginnApp());
}

class HuginnApp extends StatefulWidget {
  const HuginnApp({super.key});

  @override
  State<HuginnApp> createState() => _HuginnAppState();
}

class _HuginnAppState extends State<HuginnApp> {
  final _service = MessengerService();
  bool _loading = true;
  String? _error;
  StreamSubscription<AppEvent>? _eventSub;
  DateTime lastShown = DateTime.now();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _service.dispose();
    PlatformService.dispose();
    super.dispose();
  }

  void _onAppEvent(AppEvent event) {
    if (event is MessageEvent) {
      final msg = event.message;
      if (msg.from == _service.currentUserId) return;
      final peer = _service.peers.where((p) => p.id == msg.from).firstOrNull;
      final peerName = peer?.username ?? msg.from;
      final text = msg.text.isNotEmpty ? msg.text : (msg.files.isNotEmpty ? '[File]' : '');
      if (text.isEmpty) return;
      if (msg.timestamp.isAfter(lastShown)) {
        NotificationService.showMessageNotification(
          peerId: msg.from,
          peerName: peerName,
          text: text,
        );
        lastShown = msg.timestamp;
      }
    }
  }

  Future<void> _init() async {
    final ok = await _service.init();
    if (ok) {
      await PlatformService.init(_service);
      await NotificationService.init();
      _eventSub = _service.events.listen(_onAppEvent);
    }
    if (mounted) {
      setState(() {
        _loading = false;
        if (!ok) _error = 'Failed to init messenger';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Huginn Messenger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _error != null
              ? Scaffold(
                  appBar: AppBar(title: const Text('Huginn')),
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Error: $_error'),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _init, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : HomeScreen(service: _service),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final MessengerService service;
  const HomeScreen({super.key, required this.service});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Peer> _peers = [];
  List<GroupChat> _groups = [];
  final _searchCtrl = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    widget.service.peersStream.listen((peers) {
      if (mounted) setState(() => _peers = peers);
    });
    _loadGroups();
  }

  void _loadGroups() {
    setState(() => _groups = widget.service.getGroups());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    setState(() => _searching = q.isNotEmpty);
    if (q.isEmpty) {
      setState(() => _peers = widget.service.peers);
    } else {
      setState(() => _peers = widget.service.searchPeers(q));
    }
  }

  Future<void> _createGroup() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create group chat'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Group name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final group = await widget.service.createGroup(name);
    if (mounted) {
      if (group != null) {
        _loadGroups();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Group "$name" created')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to create group')));
      }
    }
  }

  Future<void> _refresh() async {
    _loadGroups();
    widget.service.refreshPeers();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Huginn Messenger'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsScreen(service: widget.service)),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGroup,
        icon: const Icon(Icons.group_add),
        label: const Text('New group'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search peers...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: _searching
                ? _peersList(theme, colorScheme)
                : _combinedList(theme, colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        ],
      ),
    );
  }

  Widget _combinedList(ThemeData theme, ColorScheme colorScheme) {
    if (_groups.isEmpty && _peers.isEmpty) {
      return _emptyState(Icons.chat_bubble_outline, 'No conversations yet');
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          if (_groups.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.group, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text('Groups', style: theme.textTheme.titleSmall?.copyWith(color: colorScheme.primary)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${_groups.length}', style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer)),
                  ),
                ],
              ),
            ),
            ..._groups.map((g) => _groupTile(g, theme)),
          ],
          if (_peers.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.people, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text('Peers', style: theme.textTheme.titleSmall?.copyWith(color: colorScheme.primary)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${_peers.length}', style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer)),
                  ),
                ],
              ),
            ),
            ..._peers.map((p) => _peerTile(p, theme)),
          ],
        ],
      ),
    );
  }

  Widget _peersList(ThemeData theme, ColorScheme colorScheme) {
    if (_peers.isEmpty) {
      return _emptyState(Icons.person_search, 'No peers found');
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 80),
      itemCount: _peers.length,
      itemBuilder: (_, i) => _peerTile(_peers[i], theme),
    );
  }

  Widget _groupTile(GroupChat g, ThemeData theme) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.group, color: Colors.white, size: 22),
      ),
      title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(g.uid, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              service: widget.service,
              peerId: g.uid,
              peerName: g.name,
              isGroup: true,
            ),
          ),
        );
        _loadGroups();
      },
    );
  }

  Widget _peerTile(Peer p, ThemeData theme) {
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: p.online ? Colors.green : Colors.grey[400],
            child: Text(
              (p.username ?? p.id)[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          if (p.online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(p.username ?? p.id, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(p.id, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
      trailing: p.online
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('online', style: TextStyle(fontSize: 11, color: Colors.green)),
            )
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            service: widget.service,
            peerId: p.id,
            peerName: p.username ?? p.id,
          ),
        ),
      ),
    );
  }
}

class _InviteDialog extends StatefulWidget {
  final MessengerService service;
  final String groupUid;
  const _InviteDialog({required this.service, required this.groupUid});

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  List<Peer> _peers = [];
  final _searchCtrl = TextEditingController();
  bool _inviting = false;

  @override
  void initState() {
    super.initState();
    _peers = widget.service.peers;
    widget.service.peersStream.listen((peers) {
      if (mounted) setState(() => _peers = peers);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    setState(() {
      _peers = q.isEmpty
          ? widget.service.peers
          : widget.service.searchPeers(q);
    });
  }

  Future<void> _invite(Peer peer) async {
    setState(() => _inviting = true);
    final ok = widget.service.inviteToGroup(widget.groupUid, peer.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Invited ${peer.username ?? peer.id}' : 'Failed to invite')),
      );
      if (ok) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Invite to group'),
      backgroundColor: colorScheme.surface,
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search peers...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            _inviting
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  )
                : Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _peers.length,
                      itemBuilder: (_, i) {
                        final p = _peers[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: p.online ? Colors.green : Colors.grey[400],
                            child: Text((p.username ?? p.id)[0].toUpperCase()),
                          ),
                          title: Text(p.username ?? p.id),
                          subtitle: Text(p.id, style: theme.textTheme.bodySmall),
                          onTap: () => _invite(p),
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}

class ChatScreen extends StatefulWidget {
  final MessengerService service;
  final String peerId;
  final String peerName;
  final bool isGroup;
  const ChatScreen({
    super.key,
    required this.service,
    required this.peerId,
    required this.peerName,
    this.isGroup = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<ChatMessage> _msgs = [];
  bool _loading = true;
  final List<_AttachedFile> _attachedFiles = [];

  @override
  void initState() {
    super.initState();
    _load();
    widget.service.events.listen((e) {
      if (e.type == 'message' || e.type == 'file_ready') _load();
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _load() {
    widget.service.getMessages(widget.peerId).then((msgs) {
      if (mounted) {
        msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        setState(() {
          _msgs = msgs;
          _loading = false;
        });
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final t = _msgCtrl.text.trim();
    if (t.isEmpty && _attachedFiles.isEmpty) return;

    if (_attachedFiles.isEmpty) {
      bool ok;
      ok = widget.service.sendMessage(widget.peerId, t);
      if (ok) {
        _msgCtrl.clear();
        _load();
      }
      return;
    }

    var sent = 0;
    for (var i = 0; i < _attachedFiles.length; i++) {
      final text = i == 0 ? t : '';
      final ok = widget.service.sendFile(widget.peerId, text, _attachedFiles[i].path);
      if (ok) sent++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sent > 0 ? '$sent file(s) sent' : 'Failed to send files')),
      );
      if (sent > 0) {
        _msgCtrl.clear();
        setState(() => _attachedFiles.clear());
        _load();
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    setState(() {
      for (final f in result.files) {
        if (f.path != null) {
          _attachedFiles.add(_AttachedFile(path: f.path!, name: f.name));
        }
      }
    });
  }

  void _removeFile(int index) {
    setState(() => _attachedFiles.removeAt(index));
  }

  void _invite() {
    showDialog(
      context: context,
      builder: (ctx) => _InviteDialog(service: widget.service, groupUid: widget.peerId),
    );
  }

  String _peerNameFromId(String id) {
    if (id == widget.service.currentUserId) return 'You';
    final peers = widget.service.peers;
    final found = peers.where((p) => p.id == id);
    return found.isNotEmpty ? (found.first.username ?? found.first.id) : id;
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool _isImageFile(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
  }

  Widget _buildFileRow(FileMeta f, bool own, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file, size: 14, color: own ? colorScheme.onPrimary : colorScheme.onSurface),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              f.filename.isNotEmpty ? f.filename : '[file]',
              style: TextStyle(
                fontSize: 13,
                color: own ? colorScheme.onPrimary : colorScheme.onSurface,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    bool isMe(String from) => from == widget.service.currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.peerName, style: const TextStyle(fontSize: 16)),
            if (widget.isGroup)
              Text('Group', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          ],
        ),
        centerTitle: false,
        actions: [
          if (widget.isGroup)
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Invite to group',
              onPressed: _invite,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _msgs.isEmpty
                    ? _emptyChat(theme)
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        itemCount: _msgs.length,
                        itemBuilder: (_, i) {
                          final m = _msgs[i];
                          final own = isMe(m.from);
                          return _messageBubble(m, own, theme, colorScheme);
                        },
                      ),
          ),
          if (_attachedFiles.isNotEmpty) _attachedFilesBar(colorScheme),
          _inputBar(colorScheme),
        ],
      ),
    );
  }

  Widget _emptyChat(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('No messages yet', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          const SizedBox(height: 4),
          Text('Send a message to start the conversation',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(ChatMessage m, bool own, ThemeData theme, ColorScheme colorScheme) {
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(own ? 18 : 4),
      bottomRight: Radius.circular(own ? 4 : 18),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (widget.isGroup && !own)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Text(
                _peerNameFromId(m.from),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.primary),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: own ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!own) const SizedBox(width: 8),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: own ? colorScheme.primary : colorScheme.surfaceContainerHigh,
                    borderRadius: borderRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m.files.isNotEmpty)
                        ...m.files.map((f) {
                          final isImage = _isImageFile(f.filename);
                          final filePath = widget.service.filePaths[f.fileId];
                          if (isImage && filePath != null) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(filePath),
                                  width: MediaQuery.of(context).size.width * 0.6,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => _buildFileRow(f, own, colorScheme),
                                ),
                              ),
                            );
                          }
                          return _buildFileRow(f, own, colorScheme);
                        }),
                      if (m.text.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: m.files.isNotEmpty ? 4 : 0),
                          child: Text(
                            m.text,
                            style: TextStyle(
                              color: own ? colorScheme.onPrimary : colorScheme.onSurface,
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(m.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: own ? colorScheme.onPrimary.withValues(alpha: 0.7) : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (own) const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }

  Widget _attachedFilesBar(ColorScheme colorScheme) {
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _attachedFiles.length,
        itemBuilder: (_, i) {
          final f = _attachedFiles[i];
          return Padding(
            padding: const EdgeInsets.only(right: 6, top: 8, bottom: 8),
            child: InputChip(
              avatar: const Icon(Icons.insert_drive_file, size: 16),
              label: Text(f.name, style: const TextStyle(fontSize: 13)),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () => _removeFile(i),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          );
        },
      ),
    );
  }

  Widget _inputBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            tooltip: 'Attach file',
            onPressed: _pickFile,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _msgCtrl,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: _send,
            style: FilledButton.styleFrom(
              minimumSize: const Size(46, 46),
              padding: const EdgeInsets.all(0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: const Icon(Icons.send, size: 20),
          ),
        ],
      ),
    );
  }
}

class _AttachedFile {
  final String path;
  final String name;
  _AttachedFile({required this.path, required this.name});
}

class SettingsScreen extends StatefulWidget {
  final MessengerService service;
  const SettingsScreen({super.key, required this.service});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _uCtrl, _mCtrl, _turnAddrCtrl, _turnUserCtrl, _turnPassCtrl;
  String _ttl = '1w';

  @override
  void initState() {
    super.initState();
    final c = widget.service.config;
    _uCtrl = TextEditingController(text: c.username);
    _mCtrl = TextEditingController(text: c.muninnAddr);
    _turnAddrCtrl = TextEditingController(text: c.turnAddr);
    _turnUserCtrl = TextEditingController(text: c.turnUser);
    _turnPassCtrl = TextEditingController(text: c.turnPass);
    _ttl = c.chunkTtl;
  }

  @override
  void dispose() {
    _uCtrl.dispose();
    _mCtrl.dispose();
    _turnAddrCtrl.dispose();
    _turnUserCtrl.dispose();
    _turnPassCtrl.dispose();
    super.dispose();
  }

  void _generateReloginKey() {
    final sig = widget.service.generateReloginSignature();
    if (sig == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to generate key')));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Relogin key'),
        content: SelectableText(sig, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  void _applyReloginKey() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply relogin key'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Paste relogin key here...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final ok = widget.service.applyReloginSignature(ctrl.text.trim());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ok ? 'Key applied' : 'Failed to apply key')),
              );
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _save() {
    final username = _uCtrl.text.trim();
    final oldUsername = widget.service.config.username;
    if (username != oldUsername) {
      widget.service.setUsername(username).then((ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Saved' : 'Failed')));
        }
      });
      return;
    }
    final ok = widget.service.saveConfig(AppConfig(
      username: username,
      muninnAddr: _mCtrl.text.trim(),
      chunkTtl: _ttl,
      turnAddr: _turnAddrCtrl.text.trim(),
      turnUser: _turnUserCtrl.text.trim(),
      turnPass: _turnPassCtrl.text.trim(),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Saved' : 'Failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('Account', Icons.person, colorScheme),
          const SizedBox(height: 8),
          TextField(
            controller: _uCtrl,
            decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mCtrl,
            decoration: const InputDecoration(labelText: 'Muninn server', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _ttl,
            decoration: const InputDecoration(labelText: 'Chunk TTL', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: '1d', child: Text('1 day')),
              DropdownMenuItem(value: '1w', child: Text('1 week')),
              DropdownMenuItem(value: '1m', child: Text('1 month')),
            ],
            onChanged: (v) => setState(() => _ttl = v!),
          ),
          const SizedBox(height: 24),
          _sectionHeader('TURN / STUN', Icons.router, colorScheme),
          const SizedBox(height: 8),
          TextField(
            controller: _turnAddrCtrl,
            decoration: const InputDecoration(
              labelText: 'TURN address',
              hintText: '192.168.31.250:3478',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _turnUserCtrl,
            decoration: const InputDecoration(
              labelText: 'TURN username',
              hintText: 'huginn',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _turnPassCtrl,
            decoration: const InputDecoration(
              labelText: 'TURN password',
              hintText: 'changeme',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader('Relogin', Icons.key, colorScheme),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _generateReloginKey,
                  icon: const Icon(Icons.key, size: 18),
                  label: const Text('Generate key'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _applyReloginKey,
                  icon: const Icon(Icons.vpn_key, size: 18),
                  label: const Text('Apply key'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, IconData icon, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary)),
      ],
    );
  }
}
