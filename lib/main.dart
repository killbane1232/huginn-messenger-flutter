import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'huginn_messenger.dart';
import 'src/services/platform_service.dart';
import 'src/services/notification_service.dart';

void main() {
  runApp(const HuginnApp());
}

String _peerLoginForDisplay(Iterable<Peer> peers, String identity) {
  for (final peer in peers) {
    if (peer.login == identity ||
        peer.displayLogin == identity ||
        peer.key == identity) {
      return peer.displayLogin;
    }
  }

  final separator = identity.indexOf(':');
  return separator > 0 ? identity.substring(0, separator) : identity;
}

bool _needsLoginSetup(String? username) {
  final value = username?.trim() ?? '';
  if (value.isEmpty) return true;
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}

class HuginnApp extends StatefulWidget {
  const HuginnApp({super.key});

  @override
  State<HuginnApp> createState() => _HuginnAppState();
}

class _HuginnAppState extends State<HuginnApp> {
  final _service = MessengerService();
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _loading = true;
  bool _needsLogin = false;
  String? _error;
  String? _pendingNotificationChatId;
  bool _notificationNavigationScheduled = false;
  StreamSubscription<AppEvent>? _eventSub;
  final Set<String> _notifiedMessageKeys = {};
  final List<String> _notifiedMessageOrder = [];

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
      final chatId = msg.chatId.trim().isNotEmpty ? msg.chatId : msg.from;
      final peerName = _notificationChatName(chatId, msg.from);
      final text = msg.text.isNotEmpty
          ? msg.text
          : (msg.files.isNotEmpty ? '[File]' : '');
      if (text.isEmpty) return;
      final username = _service.currentUsername;
      final userId = _service.currentUserId;
      final isOwn =
          msg.from == username ||
          msg.from == userId ||
          (username != null && msg.from.startsWith('$username:'));
      if (isOwn) return;
      if (!_markMessageForNotification(msg, chatId)) return;
      unawaited(
        NotificationService.showMessageNotification(
          chatId: chatId,
          peerName: peerName,
          text: text,
        ),
      );
    }
  }

  bool _markMessageForNotification(ChatMessage msg, String chatId) {
    final key = msg.msgId.isNotEmpty
        ? msg.msgId
        : '${msg.from}\u0000$chatId\u0000${msg.timestamp.toUtc().microsecondsSinceEpoch}'
              '\u0000${msg.text}';
    if (!_notifiedMessageKeys.add(key)) return false;

    _notifiedMessageOrder.add(key);
    const maxRememberedMessages = 256;
    if (_notifiedMessageOrder.length > maxRememberedMessages) {
      _notifiedMessageKeys.remove(_notifiedMessageOrder.removeAt(0));
    }
    return true;
  }

  String _notificationChatName(String chatId, String senderId) {
    for (final group in _service.getGroups()) {
      if (group.uid == chatId) return group.name;
    }
    return _peerLoginForDisplay(_service.peers, senderId);
  }

  void _handleNotificationTap(String chatId) {
    final value = chatId.trim();
    if (value.isEmpty) return;
    _pendingNotificationChatId = value;
    _scheduleNotificationNavigation();
  }

  void _scheduleNotificationNavigation() {
    if (_loading ||
        _error != null ||
        _needsLogin ||
        _pendingNotificationChatId == null ||
        _notificationNavigationScheduled) {
      return;
    }
    _notificationNavigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationNavigationScheduled = false;
      if (!mounted) return;
      final chatId = _pendingNotificationChatId;
      final navigator = _navigatorKey.currentState;
      if (chatId == null || navigator == null) return;

      _pendingNotificationChatId = null;
      _openNotificationChat(navigator, chatId);
    });
  }

  void _openNotificationChat(NavigatorState navigator, String chatId) {
    for (final group in _service.getGroups()) {
      if (group.uid == chatId) {
        navigator.push(
          MaterialPageRoute(
            settings: RouteSettings(name: 'chat:$chatId'),
            builder: (_) => ChatScreen(
              service: _service,
              peerId: group.uid,
              peerName: group.name,
              isGroup: true,
            ),
          ),
        );
        return;
      }
    }

    Peer? matchingPeer;
    for (final peer in _service.getPeers()) {
      if (peer.key == chatId ||
          peer.login == chatId ||
          peer.displayLogin == chatId) {
        matchingPeer = peer;
        break;
      }
    }
    navigator.push(
      MaterialPageRoute(
        settings: RouteSettings(name: 'chat:$chatId'),
        builder: (_) => ChatScreen(
          service: _service,
          peerId: matchingPeer?.key ?? chatId,
          peerName:
              matchingPeer?.displayLogin ??
              _peerLoginForDisplay(_service.peers, chatId),
        ),
      ),
    );
  }

  Future<void> _init() async {
    final ok = await _service.init();
    if (ok) {
      await PlatformService.init(_service);
      final initialChatId = await NotificationService.init(
        onNotificationTap: _handleNotificationTap,
      );
      if (initialChatId != null) {
        _pendingNotificationChatId = initialChatId;
      }
      _eventSub = _service.events.listen(_onAppEvent);
    }
    if (mounted) {
      setState(() {
        _loading = false;
        if (!ok) {
          _error = 'Failed to init messenger';
        } else {
          _needsLogin = _needsLoginSetup(_service.currentUsername);
        }
      });
      _scheduleNotificationNavigation();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
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
          : _needsLogin
          ? FirstLoginScreen(
              service: _service,
              onComplete: () {
                if (mounted) {
                  setState(() => _needsLogin = false);
                  _scheduleNotificationNavigation();
                }
              },
            )
          : HomeScreen(service: _service),
    );
  }
}

class FirstLoginScreen extends StatefulWidget {
  final MessengerService service;
  final VoidCallback onComplete;

  const FirstLoginScreen({
    super.key,
    required this.service,
    required this.onComplete,
  });

  @override
  State<FirstLoginScreen> createState() => _FirstLoginScreenState();
}

class _FirstLoginScreenState extends State<FirstLoginScreen> {
  final _loginCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _loginCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveLogin() async {
    final login = _loginCtrl.text.trim();
    if (login.isEmpty) {
      setState(() => _error = 'Enter a login');
      return;
    }
    if (_needsLoginSetup(login)) {
      setState(() => _error = 'Login cannot be a UUID');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.service.setUsername(login);
    if (!mounted) return;
    if (ok) {
      widget.onComplete();
    } else {
      setState(() {
        _busy = false;
        _error = 'Failed to save login';
      });
    }
  }

  Future<void> _scanReloginQr() async {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR scanning is only available on Android'),
        ),
      );
      return;
    }

    final signature = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ReloginQrScannerScreen()),
    );
    if (!mounted || signature == null || signature.trim().isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = widget.service.applyReloginSignature(signature.trim());
    if (!mounted) return;
    if (ok && !_needsLoginSetup(widget.service.currentUsername)) {
      widget.onComplete();
    } else {
      setState(() {
        _busy = false;
        _error = 'Failed to apply relogin QR code';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hub, size: 72, color: colorScheme.primary),
                  const SizedBox(height: 20),
                  Text(
                    'Welcome to Huginn',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose a login or restore your identity from another device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _loginCtrl,
                    autofocus: true,
                    enabled: !_busy,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Login',
                      hintText: 'Your login',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: const OutlineInputBorder(),
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _saveLogin(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _saveLogin,
                      child: const Text('Continue'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _scanReloginQr,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan relogin QR code'),
                    ),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 20),
                    const CircularProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
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
  static const _minSearchLength = 3;

  List<Peer> _peers = [];
  List<GroupChat> _groups = [];
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  StreamSubscription<List<Peer>>? _peersSub;
  StreamSubscription<AppEvent>? _eventSub;

  List<Peer> get _visiblePeers {
    final groupIds = _groups.map((group) => group.uid).toSet();
    return _peers
        .where((peer) => !groupIds.contains(peer.displayLogin))
        .toList();
  }

  List<GroupChat> get _visibleGroups {
    if (!_searching) return _groups;

    final query = _searchCtrl.text.trim().toLowerCase();
    return _groups.where((group) {
      return group.name.toLowerCase().contains(query) ||
          group.uid.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _peersSub = widget.service.peersStream.listen((peers) {
      if (mounted && !_searching) setState(() => _peers = peers);
    });
    _eventSub = widget.service.events.listen((event) {
      if (event is MessageEvent) _loadGroups();
    });
    _loadGroups();
    _loadPeers();
  }

  void _loadGroups() {
    final groups = widget.service.getGroups();
    if (mounted) setState(() => _groups = groups);
  }

  void _loadPeers() {
    final peers = widget.service.getPeers();
    if (mounted) setState(() => _peers = peers);
  }

  @override
  void dispose() {
    _peersSub?.cancel();
    _eventSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    final query = q.trim();
    if (query.length < _minSearchLength) {
      setState(() {
        _searching = false;
        _peers = widget.service.peers;
      });
      return;
    }

    final peers = widget.service.searchPeers(query);
    setState(() {
      _searching = true;
      _peers = peers;
    });
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final group = await widget.service.createGroup(name);
    if (mounted) {
      if (group != null) {
        _loadGroups();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Group "$name" created')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to create group')));
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
              MaterialPageRoute(
                builder: (_) => SettingsScreen(service: widget.service),
              ),
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
                hintText: 'Search peers or groups (3+ characters)...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
              ),
              onChanged: _search,
            ),
          ),
          Expanded(child: _combinedList(theme, colorScheme)),
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
    final peers = _visiblePeers;
    final groups = _visibleGroups;
    if (groups.isEmpty && peers.isEmpty) {
      return _emptyState(
        _searching ? Icons.search_off : Icons.chat_bubble_outline,
        _searching ? 'No peers or groups found' : 'No conversations yet',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          if (groups.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.group, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Groups',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${groups.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...groups.map(_groupTile),
          ],
          if (peers.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.people, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Peers',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${peers.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...peers.map((p) => _peerTile(p, theme)),
          ],
        ],
      ),
    );
  }

  Widget _groupTile(GroupChat g) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.group, color: Colors.white, size: 22),
      ),
      title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w500)),
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
              p.displayLogin.isNotEmpty ? p.displayLogin[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
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
                  border: Border.all(
                    color: theme.scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        p.displayLogin,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      trailing: p.online
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'online',
                style: TextStyle(fontSize: 11, color: Colors.green),
              ),
            )
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            service: widget.service,
            peerId: p.key,
            peerName: p.displayLogin,
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
  static const _minSearchLength = 3;

  List<Peer> _peers = [];
  final _searchCtrl = TextEditingController();
  bool _inviting = false;
  bool _searching = false;
  StreamSubscription<List<Peer>>? _peersSub;

  @override
  void initState() {
    super.initState();
    _peers = widget.service.getPeers();
    _peersSub = widget.service.peersStream.listen((peers) {
      if (mounted && !_searching) setState(() => _peers = peers);
    });
  }

  @override
  void dispose() {
    _peersSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    final query = q.trim();
    final searching = query.length >= _minSearchLength;
    final peers = searching
        ? widget.service.searchPeers(query)
        : widget.service.peers;
    setState(() {
      _searching = searching;
      _peers = peers;
    });
  }

  Future<void> _invite(Peer peer) async {
    setState(() => _inviting = true);
    final ok = widget.service.inviteToGroup(widget.groupUid, peer.key);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Invited ${peer.displayLogin}' : 'Failed to invite',
          ),
        ),
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
                hintText: 'Search peers (3+ characters)...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
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
                            backgroundColor: p.online
                                ? Colors.green
                                : Colors.grey[400],
                            child: Text(
                              p.displayLogin.isNotEmpty
                                  ? p.displayLogin[0].toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: Text(p.displayLogin),
                          onTap: () => _invite(p),
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
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

enum _MessageAction { reply, forward }

class _ForwardTarget {
  final String id;
  final String name;
  final bool isGroup;

  const _ForwardTarget({
    required this.id,
    required this.name,
    required this.isGroup,
  });
}

class _ChatScreenState extends State<ChatScreen> {
  static const _stickerCategories = <String, List<String>>{
    'Радость': [
      '(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧',
      '٩(◕‿◕｡)۶',
      'ヽ(•‿•)ノ',
      '(*^ω^) (´∀｀*)',
      '(o^▽^o)',
      '(⌒▽⌒)☆',
      '<(￣︶￣)>',
      '(*⌒―⌒*)))',
      'ヽ(・∀・)ﾉ',
      '(´｡• ω •｡`)',
      '(￣ω￣) ｀;:',
      ';｀;･(゜ε゜ )',
      '(o･ω･o)',
      '(＠＾－＾)',
      'ヽ(*・ω・)ﾉ',
      '(o_ _)ﾉ彡☆',
      '(^人^)',
      '(o´▽`o)',
      '(*´▽`*)',
      '｡ﾟ( ﾟ^∀^ﾟ)ﾟ｡',
      '(´ω｀)',
      '(☆▽☆)',
      '(≧◡≦)',
      '(o´∀｀o)',
      '(´• ω •`)',
      '(＾▽＾)',
      '(⌒ω⌒)',
      '∑d(ﾟ∀ﾟd)',
      '╰(▔∀▔)╯',
      '(─‿‿─)',
      '(*^‿^*)',
      'ヽ(o^―^o)ﾉ',
      '(✯◡✯)',
      '(◕‿◕)',
      '(*≧ω≦*)',
      '(((o(*ﾟ▽ﾟ*)o)))',
      '(⌒‿⌒)',
      '＼(≧▽≦)／',
      '⌒(o＾▽＾o)ノ ☆',
      '～(`▽^人)',
      '(*ﾟ▽ﾟ*)',
      '(✧∀✧)',
      '(✧ω✧)',
      'ヽ(*⌒▽⌒*)ﾉ',
      '(´｡• ᵕ •｡`)',
      '( ´ ▽ ` )',
      '(￣▽￣)',
      '╰(*´︶`*)╯',
      'ヽ(>∀<☆)ノ',
      'o(≧▽≦)o',
      '(☆ω☆)',
      '(っ˘ω˘ς )',
      '＼(￣▽￣)／',
      '(*¯︶¯*)',
      '＼(＾▽＾)／',
      '٩(◕‿◕)۶',
      '(o˘◡˘o)',
    ],
    'Любовь': [
      '(づ｡◕‿‿◕｡)づ',
      '(｡♥‿♥｡)',
      '(ﾉ´з｀)ノ',
      '(♡μ_μ)',
      '(*^^*)♡'
          '(♡-_-♡)',
      '(￣ε￣＠)',
      'ヽ(♡‿♡)ノ ( ´∀｀)ノ～ ♡',
      '(─‿‿─)♡',
      '(´｡• ᵕ •｡`)♡',
      '(*♡∀♡)',
      '(｡・//ε//・｡)',
      '(´ω｀♡)',
      '( ◡‿◡ ♡)',
      '(◕‿◕)♡',
      '(/▽＼*)｡o○♡',
      '(ღ˘⌣˘ღ)',
      '(♡ﾟ▽ﾟ♡)',
      '♡(。-ω-)',
      '♡ ～(`▽^人)',
      '(´• ω •`)',
      '♡',
      '(´ε｀ )♡',
      '(´｡• ω •｡`)',
      '♡',
      '( ´ ▽ ` ).｡ｏ♡',
      '╰(*´︶`*)╯♡',
      '(*˘︶˘*).｡.:*♡',
      '(♡˙︶˙♡)',
      '♡＼(￣▽￣)／♡',
      '(≧◡≦)',
      '♡',
      '(⌒▽⌒)♡',
      '(*¯ ³¯*)♡',
      '(っ˘з(˘⌣˘ )',
      '♡',
      '♡ (˘▽˘>ԅ( ˘⌣˘)',
      '( ˘⌣˘)♡(˘⌣˘ )',
      '(/^-^(^ ^*)/',
      '♡',
    ],
    'Смущение': [
      '(⌒_⌒;)',
      '(o^ ^o)',
      '(*/ω＼)',
      '(*/。＼)',
      '(*/_＼)',
      '(*ﾉωﾉ)',
      '(o-_-o)',
      '(*μ_μ)',
      '( ◡‿◡ *)',
      '(ᵔ.ᵔ)',
      '(*ﾉ∀`*)',
      '(//▽//)',
      '(//ω//)',
      '(ノ*ﾟ▽ﾟ*)',
      '(*^.^*)',
      '(*ﾉ▽ﾉ)',
      '(￣▽￣*)ゞ',
      '(⁄ ⁄•⁄ω⁄•⁄ ⁄)',
      '(*/▽＼*)',
    ],
    'Недовольство': [
      '(＃＞＜)',
      '(；⌣̀_⌣́)',
      '☆ｏ(＞＜；)○',
      '(￣ ￣|||)',
      '(；￣Д￣)',
      '(￣□￣」)',
      '(＃￣0￣)',
      '(＃￣ω￣)',
      '(￢_￢;)',
      '(＞ｍ＜)',
      '(」゜ロ゜)」',
      '(〃＞＿＜;〃)',
      '(＾＾＃)',
      '(︶︹︺)',
      '(￣ヘ￣)',
      '<(￣ ﹌ ￣)>',
      '(￣︿￣)',
      '(＞﹏＜)',
      '(--_--)',
      '凸(￣ヘ￣)',
      'ヾ( ￣O￣)ツ',
      '(⇀‸↼‶)',
      'o(>< )o',
    ],
    'Злость': [
      '(╯°益°)╯彡┻━┻',
      '(ง •̀_•́)ง',
      'ಠ_ಠ',
      '(＃`Д´)',
      '(╬ಠ益ಠ)'
          '(｀皿´＃)',
      '(｀ω´)',
      'ヽ( `д´*)ノ',
      '(・｀ω´・)',
      '(｀ー´)',
      'ヽ(｀⌒´メ)ノ',
      '凸(｀△´＃)',
      '(｀ε´)',
      'ψ(｀∇´)ψ',
      'ヾ(｀ヘ´)ﾉﾞ',
      'ヽ(‵﹏′)ノ',
      '(ﾒ｀ﾛ´)',
      '(╬｀益´)',
      '┌∩┐(◣_◢)┌∩┐',
      '凸(｀ﾛ´)凸',
      'Σ(▼□▼メ)',
      '(°ㅂ°╬)',
      'ψ(▼へ▼メ)～→',
      '(ノ°益°)ノ',
      '(҂ `з´ )',
      '(‡▼益▼)',
      '(҂｀ﾛ´)凸 ((╬◣﹏◢))',
      '٩(╬ʘ益ʘ╬)۶',
      '(╬ Ò﹏Ó)',
      '＼＼٩(๑`^´๑)۶／／',
    ],
    'Удивление': [
      '(⊙_⊙)',
      '(°ロ°) !',
      'Σ(°△°|||)',
      '(☉_☉)'
          '(￣ω￣;)',
      'σ(￣、￣〃)',
      '(￣～￣;)',
      '(-_-;)・・・',
      '┐(`～`;)┌',
      '(・_・ヾ',
      '(〃￣ω￣〃ゞ',
      '┐(￣ヘ￣;)┌',
      '(・_・;)',
      '(￣_￣)・・・',
      '╮(￣ω￣;)╭',
      '(￣.￣;)',
      '(＠_＠)',
      '(・・;)ゞ',
      'Σ(￣。￣ﾉ)',
      '(・・ )?',
      '(•ิ_•ิ)?',
      '(◎ ◎)ゞ',
      '(ーー;)',
      'w(ﾟｏﾟ)w ヽ(ﾟ〇ﾟ)ﾉ Σ(O_O) Σ(ﾟロﾟ)',
      '(⊙_⊙)',
      '(o_O)',
      '(O_O;)',
      '(O.O)',
      '(ﾟロﾟ)',
      '! (o_O) !',
      '(□_□)',
      'Σ(□_□)',
      '∑(O_O;)',
    ],
    'Сомнение': [
      '(￢_￢)',
      '(→_→)',
      '(￢ ￢)',
      '(￢‿￢ )',
      '(¬_¬ )',
      '(←_←)',
      '(¬ ¬ )',
      '(¬‿¬ )',
      '(↼_↼)',
      '(⇀_⇀)',
    ],
    'Приветствие': [
      '(*・ω・)ﾉ',
      '(￣▽￣)ノ',
      '(ﾟ▽ﾟ)/',
      '(*´∀｀)ﾉ',
      '(^-^*)/',
      '(＠´ー`)ﾉﾞ',
      '(´• ω •`)ﾉ',
      '(ﾟ∀ﾟ)ﾉﾞ',
      'ヾ(*`▽`*)',
      '＼(⌒▽⌒)',
      'ヾ(☆▽☆)',
      '( ´ ▽ ` )ﾉ',
      '(^０^)ノ',
      '~ヾ(・ω・)',
      '(・∀・)ノ',
      'ヾ(^ω^*)',
      '(*ﾟｰﾟ)ﾉ',
      '(・_・)ノ',
      '(o´ω`o)ﾉ',
      'ヾ(☆\'∀\'☆)',
      '(￣ω￣)/',
      '(´ω｀)ノﾞ',
      '(⌒ω⌒)ﾉ',
      '(o^ ^o)/',
      '(≧▽≦)/',
      '(✧∀✧)/',
      '(o´▽`o)ﾉ',
      '(￣▽￣)/',
    ],
    'Грусть': [
      '(ಥ﹏ಥ)',
      '(｡•́︿•̀｡)',
      '(╥_╥)',
      '(っ˘̩╭╮˘̩)っ'
          '(ノ_<。)',
      '(*-_-)',
      '(´-ω-｀)',
      '.･ﾟﾟ･(／ω＼)･ﾟﾟ･.',
      '(μ_μ)',
      '(ﾉД`)',
      '(-ω-、)',
      '。゜゜(´Ｏ｀)°゜。',
      'o(TヘTo)',
      '(；ω；)',
      '(｡╯3╰｡)',
      '｡･ﾟﾟ*(>д<)*ﾟﾟ･｡',
      '( ﾟ，_ゝ｀)',
      '(个_个)',
      '(╯︵╰,)',
      '｡･ﾟ(ﾟ><ﾟ)ﾟ･｡',
      '( ╥ω╥ )',
      '(╯_╰)',
      '(╥_╥)',
      '.｡･ﾟﾟ･(＞_＜)･ﾟﾟ･｡.',
      '(／ˍ・、)',
      '(ノ_<、)',
      '(╥﹏╥)',
      '｡ﾟ(｡ﾉωヽ｡)ﾟ｡',
      '(つω`*)',
      '(｡T ω T｡)',
      '(ﾉω･､)',
      '･ﾟ･(｡>ω<｡)･ﾟ･',
      '(T_T)',
      '(>_<)',
      '(Ｔ▽Ｔ)',
      '｡ﾟ･ (>﹏<) ･ﾟ｡',
      'o(〒﹏〒)o',
    ],
    'Спокойствие': [
      '┬─┬ノ( º _ ºノ)',
      '¯\\_(ツ)_/¯',
      '(⌐■_■)',
      'ʕ•ᴥ•ʔ',
      '◯０o。(ー。ー)y~~',
      'ヽ(ー_ー )ノ',
      'ヽ(´ー｀)┌',
      '┐(‘～` )┌',
      'ヽ(　￣д￣)ノ',
      '┐(￣ヘ￣)┌',
      'ヽ(￣～￣　)ノ',
      '╮(￣_￣)╭',
      'ヽ(ˇヘˇ)ノ',
      '┐(￣～￣)┌',
      '┐(︶▽︶)┌',
      '╮(￣～￣)╭',
      '¯＼_(ツ)_/¯',
      '┐(´д｀)┌',
      '╮(︶︿︶)╭',
      '┐(￣∀￣)┌',
      '┐( ˘ ､ ˘ )┌',
    ],
    'Секрет': [
      '''ЗАПУСКАЕМ
░ГУСЯ░▄▀▀▀▄░РАБОТЯГИ░░
▄███▀░◐░░░▌░░░░░░░
░░░░▌░░░░░▐░░░░░░░
░░░░▐░░░░░▐░░░░░░░
░░░░▌░░░░░▐▄▄░░░░░
░░░░▌░░░░▄▀▒▒▀▀▀▀▄
░░░▐░░░░▐▒▒▒▒▒▒▒▒▀▀▄
░░░▐░░░░▐▄▒▒▒▒▒▒▒▒▒▒▀▄
░░░░▀▄░░░░▀▄▒▒▒▒▒▒▒▒▒▒▀▄
░░░░░░▀▄▄▄▄▄█▄▄▄▄▄▄▄▄▄▄▄▀▄
░░░░░░░░░░░▌▌░▌▌░░░░░
░░░░░░░░░░░▌▌░▌▌░░░░░
░░░░░░░░░▄▄▌▌▄▌▌░░░░░''',
    ],
  };

  final _msgCtrl = TextEditingController();
  final _msgFocus = FocusNode();
  final _scrollCtrl = ScrollController();
  List<ChatMessage> _msgs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _allLoaded = false;
  int _loadedOlderCount = 0;
  static const int _pageSize = 64;
  StreamSubscription<AppEvent>? _eventSub;
  final List<_AttachedFile> _attachedFiles = [];
  ChatMessage? _replyingTo;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _eventSub = widget.service.events.listen(_onEvent);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _msgFocus.dispose();
    _scrollCtrl.dispose();
    _eventSub?.cancel();
    super.dispose();
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

    final text = _replyingTo == null ? t : _replyText(_replyingTo!, t);

    if (_attachedFiles.isEmpty) {
      bool ok;
      ok = widget.service.sendMessage(widget.peerId, text);
      if (ok) {
        _msgCtrl.clear();
        if (_replyingTo != null) {
          setState(() => _replyingTo = null);
        }
      }
      return;
    }

    var sent = 0;
    for (var i = 0; i < _attachedFiles.length; i++) {
      final ok = widget.service.sendFile(
        widget.peerId,
        text,
        _attachedFiles[i].path,
      );
      if (ok) sent++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent > 0 ? '$sent file(s) sent' : 'Failed to send files',
          ),
        ),
      );
      if (sent > 0) {
        _msgCtrl.clear();
        setState(() {
          _attachedFiles.clear();
          _replyingTo = null;
        });
      }
    }
  }

  bool _sendSticker(String sticker) {
    final text = _replyingTo == null
        ? sticker
        : _replyText(_replyingTo!, sticker);
    final ok = widget.service.sendMessage(widget.peerId, text);
    if (ok && _replyingTo != null) {
      setState(() => _replyingTo = null);
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to send sticker')));
    }
    return ok;
  }

  String _messagePreview(ChatMessage message) {
    final textPreview = FormattedMessageText.makePreview(message.text);
    if (textPreview.isNotEmpty) return textPreview;
    if (message.files.isEmpty) return '';
    final filename = message.files.first.filename;
    return filename.isEmpty ? '[File]' : '[File: $filename]';
  }

  String _replyText(ChatMessage message, String body) {
    return FormattedMessageText.encodeReply(
      author: _messageAuthorForFormatting(message),
      preview: _messagePreview(message),
      body: body,
    );
  }

  String _messageAuthorForFormatting(ChatMessage message) {
    final displayName = _peerNameForDisplay(message.from);
    if (displayName != 'You') return displayName;
    return widget.service.currentUsername ?? displayName;
  }

  void _startReply(ChatMessage message) {
    setState(() => _replyingTo = message);
    _msgFocus.requestFocus();
  }

  List<_ForwardTarget> _forwardTargets() {
    final groups = widget.service.getGroups();
    final refreshedPeers = widget.service.getPeers();
    final peers = refreshedPeers.isEmpty
        ? widget.service.peers
        : refreshedPeers;
    final groupIds = groups.map((group) => group.uid).toSet();
    final targets = <_ForwardTarget>[
      ...groups.map(
        (group) =>
            _ForwardTarget(id: group.uid, name: group.name, isGroup: true),
      ),
      ...peers
          .where((peer) => !groupIds.contains(peer.displayLogin))
          .map(
            (peer) => _ForwardTarget(
              id: peer.key,
              name: peer.displayLogin,
              isGroup: false,
            ),
          ),
    ];
    final seen = <String>{};
    return targets.where((target) => seen.add(target.id)).toList();
  }

  Future<_ForwardTarget?> _chooseForwardTarget() {
    final targets = _forwardTargets();
    return showModalBottomSheet<_ForwardTarget>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Forward to',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              if (targets.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Text('No conversations available'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: targets.length,
                    itemBuilder: (_, index) {
                      final target = targets[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            target.isGroup ? Icons.group : Icons.person,
                          ),
                        ),
                        title: Text(target.name),
                        onTap: () => Navigator.pop(sheetContext, target),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _forwardMessage(ChatMessage message) async {
    final target = await _chooseForwardTarget();
    if (target == null || !mounted) return;

    final parsed = FormattedMessageText.parse(message.text);
    final body = parsed.body;
    final author = parsed.forwardedFrom ?? _messageAuthorForFormatting(message);
    final formattedText = FormattedMessageText.forward(
      author: author,
      body: body,
    );
    final filePaths = message.files
        .map((file) => file.resolveLocalPath(widget.service.filePaths))
        .whereType<String>()
        .where((path) => File(path).existsSync())
        .toList();

    var sent = false;
    if (filePaths.isEmpty) {
      if (body.isNotEmpty) {
        sent = widget.service.sendMessage(target.id, formattedText);
      }
    } else {
      for (var i = 0; i < filePaths.length; i++) {
        final attachmentText = i == 0
            ? formattedText
            : FormattedMessageText.forward(
                author: author,
                body: '[Attachment]',
              );
        sent =
            widget.service.sendFile(target.id, attachmentText, filePaths[i]) ||
            sent;
      }
    }

    if (!mounted) return;
    final missingFiles = filePaths.length < message.files.length;
    final text = sent
        ? missingFiles
              ? 'Message forwarded; unavailable attachments were skipped'
              : 'Message forwarded'
        : message.files.isNotEmpty
        ? 'Attachment is not available for forwarding'
        : 'Failed to forward message';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showDesktopMessageMenu(
    ChatMessage message,
    TapDownDetails details,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<_MessageAction>(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: _MessageAction.reply,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.reply),
            title: Text('Reply'),
          ),
        ),
        PopupMenuItem(
          value: _MessageAction.forward,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.forward),
            title: Text('Forward'),
          ),
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _MessageAction.reply:
        _startReply(message);
      case _MessageAction.forward:
        await _forwardMessage(message);
      case null:
        break;
    }
  }

  Widget _stickerGrid(BuildContext sheetContext, List<String> stickers) {
    final colorScheme = Theme.of(sheetContext).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 72,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: stickers.length,
      itemBuilder: (_, index) {
        final sticker = stickers[index];
        return OutlinedButton(
          onPressed: () {
            if (_sendSticker(sticker)) {
              Navigator.of(sheetContext).pop();
            }
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.onSurface,
            side: BorderSide(color: colorScheme.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            sticker,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
        );
      },
    );
  }

  void _showStickers() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.55,
            child: DefaultTabController(
              length: _stickerCategories.length,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'Стикеры',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                  TabBar(
                    isScrollable: true,
                    tabs: _stickerCategories.keys
                        .map((category) => Tab(text: category))
                        .toList(),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: _stickerCategories.values
                          .map(
                            (stickers) => _stickerGrid(sheetContext, stickers),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
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
      builder: (ctx) =>
          _InviteDialog(service: widget.service, groupUid: widget.peerId),
    );
  }

  String _peerNameForDisplay(String identity) {
    final username = widget.service.currentUsername;
    final userId = widget.service.currentUserId;
    if (identity == username ||
        identity == userId ||
        (username != null && identity.startsWith('$username:'))) {
      return 'You';
    }
    return _peerLoginForDisplay(widget.service.peers, identity);
  }

  String _formatTime(DateTime dt) {
    final localTime = dt.toLocal();
    final h = localTime.hour.toString().padLeft(2, '0');
    final m = localTime.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool _isImageFile(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
  }

  Widget _buildFileRow(FileMeta f, bool own, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openFile(f),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.attach_file,
                size: 14,
                color: own ? colorScheme.onPrimary : colorScheme.onSurface,
              ),
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
        ),
      ),
    );
  }

  Future<void> _openFile(FileMeta file) async {
    final path = file.resolveLocalPath(widget.service.filePaths);
    if (path == null || path.isEmpty || !await File(path).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File is not available yet')),
        );
      }
      return;
    }

    final opened = await PlatformService.openFile(path);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No app could open this file')),
      );
    }
  }

  void _onEvent(AppEvent e) {
    if (e is MessageEvent) {
      final msg = e.message;
      if (msg.chatId.isEmpty) {
        unawaited(_appendLegacyEventIfCurrent(msg));
        return;
      }
      if (msg.chatId != widget.peerId) return;
      _appendMessage(msg);
    } else if (e is FileReadyEvent &&
        _msgs.any(
          (message) => message.files.any((file) => file.fileId == e.fileId),
        )) {
      setState(() {});
    }
  }

  void _appendMessage(ChatMessage message) {
    if (message.msgId.isNotEmpty &&
        _msgs.any((item) => item.msgId == message.msgId)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _msgs.add(message);
      _msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
    _scrollToBottom();
  }

  Future<void> _appendLegacyEventIfCurrent(ChatMessage eventMessage) async {
    if (eventMessage.msgId.isEmpty) return;
    final latest = await widget.service.getMessagesPaginated(
      widget.peerId,
      limit: _pageSize,
      offset: 0,
    );
    if (!mounted) return;
    final matching = latest.where(
      (message) => message.msgId == eventMessage.msgId,
    );
    if (matching.isNotEmpty) _appendMessage(matching.first);
  }

  void _onScroll() {
    if (_scrollCtrl.offset <= 100 &&
        !_loadingMore &&
        !_allLoaded &&
        _msgs.isNotEmpty) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    final msgs = await widget.service.getMessagesPaginated(
      widget.peerId,
      limit: _pageSize,
      offset: 0,
    );
    if (!mounted) return;
    setState(() {
      _msgs = msgs;
      _loadedOlderCount = msgs.length;
      _allLoaded = msgs.length < _pageSize;
      _loading = false;
    });
    _scrollToBottom();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _allLoaded) return;
    setState(() => _loadingMore = true);
    final oldMax = _scrollCtrl.hasClients
        ? _scrollCtrl.position.maxScrollExtent
        : 0.0;
    final olderMsgs = await widget.service.getMessagesPaginated(
      widget.peerId,
      limit: _pageSize,
      offset: _loadedOlderCount,
    );
    if (!mounted) return;
    setState(() {
      if (olderMsgs.isNotEmpty) {
        _msgs = [...olderMsgs, ..._msgs];
        _loadedOlderCount += olderMsgs.length;
      }
      if (olderMsgs.length < _pageSize) {
        _allLoaded = true;
      }
      _loadingMore = false;
    });
    if (olderMsgs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          final newMax = _scrollCtrl.position.maxScrollExtent;
          _scrollCtrl.jumpTo(_scrollCtrl.offset + (newMax - oldMax));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    bool isMe(String from) {
      final username = widget.service.currentUsername;
      final userId = widget.service.currentUserId;
      return from == username ||
          from == userId ||
          (username != null && from.startsWith('$username:'));
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.peerName, style: const TextStyle(fontSize: 16)),
            if (widget.isGroup)
              Text(
                'Group',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
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
                    itemCount: _msgs.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (_loadingMore && i == 0) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final idx = _loadingMore ? i - 1 : i;
                      final m = _msgs[idx];
                      final own = isMe(m.from);
                      return _interactiveMessage(m, own, theme, colorScheme);
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
          Text(
            'No messages yet',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Send a message to start the conversation',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(
    ChatMessage m,
    bool own,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final formatted = FormattedMessageText.parse(m.text);
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(own ? 18 : 4),
      bottomRight: Radius.circular(own ? 4 : 18),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: own
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (widget.isGroup && !own)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Text(
                _peerNameForDisplay(m.from),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: own
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              if (!own) const SizedBox(width: 8),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: own
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHigh,
                    borderRadius: borderRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (formatted.reply case final reply?)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
                          decoration: BoxDecoration(
                            color: own
                                ? colorScheme.onPrimary.withValues(alpha: 0.12)
                                : colorScheme.primary.withValues(alpha: 0.09),
                            border: Border(
                              left: BorderSide(
                                width: 3,
                                color: own
                                    ? colorScheme.onPrimary
                                    : colorScheme.primary,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _peerNameForDisplay(reply.author),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: own
                                      ? colorScheme.onPrimary
                                      : colorScheme.primary,
                                ),
                              ),
                              Text(
                                reply.preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: own
                                      ? colorScheme.onPrimary.withValues(
                                          alpha: 0.85,
                                        )
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (formatted.forwardedFrom case final author?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.forward,
                                size: 14,
                                color: own
                                    ? colorScheme.onPrimary.withValues(
                                        alpha: 0.85,
                                      )
                                    : colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Forwarded from ${_peerNameForDisplay(author)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: own
                                        ? colorScheme.onPrimary.withValues(
                                            alpha: 0.85,
                                          )
                                        : colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (m.files.isNotEmpty)
                        ...m.files.map((f) {
                          final isImage = _isImageFile(f.filename);
                          final filePath = f.resolveLocalPath(
                            widget.service.filePaths,
                          );
                          if (isImage && filePath != null) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: GestureDetector(
                                onTap: () => _openFile(f),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight:
                                          MediaQuery.sizeOf(context).height *
                                          0.6,
                                    ),
                                    child: Image.file(
                                      File(filePath),
                                      width:
                                          MediaQuery.sizeOf(context).width *
                                          0.6,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) =>
                                          _buildFileRow(f, own, colorScheme),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          return _buildFileRow(f, own, colorScheme);
                        }),
                      if (formatted.body.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(
                            top: m.files.isNotEmpty ? 4 : 0,
                          ),
                          child: Text(
                            formatted.body,
                            style: TextStyle(
                              color: own
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(m.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: own
                              ? colorScheme.onPrimary.withValues(alpha: 0.7)
                              : colorScheme.onSurfaceVariant,
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

  Widget _interactiveMessage(
    ChatMessage message,
    bool own,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    Widget child = _messageBubble(message, own, theme, colorScheme);

    if (Platform.isAndroid) {
      child = GestureDetector(
        onLongPress: () => _forwardMessage(message),
        child: Dismissible(
          key: ValueKey(
            message.msgId.isNotEmpty
                ? message.msgId
                : '${message.from}-${message.timestamp.microsecondsSinceEpoch}-${message.text.hashCode}',
          ),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) async {
            _startReply(message);
            return false;
          },
          background: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.only(right: 22),
            alignment: Alignment.centerRight,
            color: colorScheme.primaryContainer.withValues(alpha: 0.55),
            child: Icon(Icons.reply, color: colorScheme.onPrimaryContainer),
          ),
          child: SizedBox(width: double.infinity, child: child),
        ),
      );
    } else if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      child = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (details) =>
            _showDesktopMessageMenu(message, details),
        child: child,
      );
    }

    return child;
  }

  Widget _attachedFilesBar(ColorScheme colorScheme) {
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
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
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingTo case final message?)
            Container(
              margin: const EdgeInsets.fromLTRB(48, 0, 4, 8),
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.65,
                ),
                border: Border(
                  left: BorderSide(color: colorScheme.primary, width: 3),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _peerNameForDisplay(message.from),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _messagePreview(message),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Cancel reply',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _replyingTo = null),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file),
                tooltip: 'Attach file',
                onPressed: _pickFile,
              ),
              IconButton(
                icon: const Icon(Icons.emoji_emotions_outlined),
                tooltip: 'Stickers',
                onPressed: _showStickers,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  focusNode: _msgFocus,
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
                    fillColor: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Icon(Icons.send, size: 20),
              ),
            ],
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
  late TextEditingController _uCtrl,
      _mCtrl,
      _turnAddrCtrl,
      _turnUserCtrl,
      _turnPassCtrl;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to generate key')));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Relogin key'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: sig,
                    size: 280,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Scan this code on the device that should use this identity.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Show text key'),
                  children: [
                    SelectableText(
                      sig,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool get _canScanQr => Platform.isAndroid;

  Future<void> _scanReloginKey() async {
    if (!_canScanQr) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR scanning is not supported on this platform'),
        ),
      );
      return;
    }

    final signature = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ReloginQrScannerScreen()),
    );
    if (!mounted || signature == null || signature.trim().isEmpty) return;

    final ok = widget.service.applyReloginSignature(signature.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Key applied' : 'Failed to apply key')),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final ok = widget.service.applyReloginSignature(ctrl.text.trim());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok ? 'Key applied' : 'Failed to apply key'),
                ),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(ok ? 'Saved' : 'Failed')));
        }
      });
      return;
    }
    final ok = widget.service.saveConfig(
      AppConfig(
        username: username,
        muninnAddr: _mCtrl.text.trim(),
        chunkTtl: _ttl,
        turnAddr: _turnAddrCtrl.text.trim(),
        turnUser: _turnUserCtrl.text.trim(),
        turnPass: _turnPassCtrl.text.trim(),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ok ? 'Saved' : 'Failed')));
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
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mCtrl,
            decoration: const InputDecoration(
              labelText: 'Muninn server',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _ttl,
            decoration: const InputDecoration(
              labelText: 'Chunk TTL',
              border: OutlineInputBorder(),
            ),
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
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _scanReloginKey,
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Scan relogin QR code'),
            ),
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
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _ReloginQrScannerScreen extends StatefulWidget {
  const _ReloginQrScannerScreen();

  @override
  State<_ReloginQrScannerScreen> createState() =>
      _ReloginQrScannerScreenState();
}

class _ReloginQrScannerScreenState extends State<_ReloginQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _resultReturned = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_resultReturned) return;
    String? value;
    for (final barcode in capture.barcodes) {
      final candidate = barcode.rawValue?.trim();
      if (candidate != null && candidate.isNotEmpty) {
        value = candidate;
        break;
      }
    }
    if (value == null) return;

    _resultReturned = true;
    await _controller.stop();
    if (mounted) Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan relogin QR code')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Text(
              'Point the camera at a Huginn relogin QR code',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
