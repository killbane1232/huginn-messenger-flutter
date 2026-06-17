import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'huginn_messenger.dart';

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

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final ok = await _service.init();
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
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
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
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
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
    if (q.isEmpty) {
      setState(() => _peers = widget.service.peers);
    } else {
      setState(() => _peers = widget.service.searchPeers(q));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Huginn Messenger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsScreen(service: widget.service)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search peers...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: _peers.isEmpty
                ? const Center(child: Text('No peers'))
                : ListView.builder(
                    itemCount: _peers.length,
                    itemBuilder: (_, i) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _peers[i].online ? Colors.green : Colors.grey,
                        child: Text((_peers[i].username ?? _peers[i].id)[0].toUpperCase()),
                      ),
                      title: Text(_peers[i].username ?? _peers[i].id),
                      subtitle: Text(_peers[i].id, style: Theme.of(context).textTheme.bodySmall),
                      trailing: _peers[i].online
                          ? const Icon(Icons.circle, size: 12, color: Colors.green)
                          : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(service: widget.service, peerId: _peers[i].id, peerName: _peers[i].username ?? _peers[i].id),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final MessengerService service;
  final String peerId;
  final String peerName;
  const ChatScreen({super.key, required this.service, required this.peerId, required this.peerName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<ChatMessage> _msgs = [];

  @override
  void initState() {
    super.initState();
    _load();
    widget.service.events.listen((e) {
      if (e.type == 'message') _load();
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
        setState(() => _msgs = msgs);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
      }
    });
  }

  void _send() {
    final t = _msgCtrl.text.trim();
    if (t.isEmpty) return;
    if (widget.service.sendMessage(widget.peerId, t)) {
      _msgCtrl.clear();
      _load();
    }
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final text = _msgCtrl.text.trim();
    final ok = widget.service.sendFile(widget.peerId, text, path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'File sent' : 'Failed to send file')),
      );
      if (ok) {
        _msgCtrl.clear();
        _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.peerName)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(8),
              itemCount: _msgs.length,
              itemBuilder: (_, i) {
                final m = _msgs[i];
                final isMe = m.from == widget.service.currentUserId;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blue[100] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (m.files.isNotEmpty) Text('[${m.files.length} file(s)]', style: const TextStyle(fontSize: 12)),
                        Text(m.text),
                        Text(
                          '${m.timestamp.hour}:${m.timestamp.minute.toString().padLeft(2, '0')}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _pickAndSendFile,
                ),
                const SizedBox(width: 4),
                IconButton(icon: const Icon(Icons.send), onPressed: _send),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

  void _save() {
    final ok = widget.service.saveConfig(AppConfig(
      username: _uCtrl.text.trim(),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _uCtrl, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _mCtrl, decoration: const InputDecoration(labelText: 'Muninn server', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _ttl,
            decoration: const InputDecoration(labelText: 'Chunk TTL', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: '1d', child: Text('1 day')),
              DropdownMenuItem(value: '1w', child: Text('1 week')),
              DropdownMenuItem(value: '1m', child: Text('1 month')),
            ],
            onChanged: (v) => setState(() => _ttl = v!),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const Text('TURN / STUN Server', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _turnAddrCtrl, decoration: const InputDecoration(
            labelText: 'TURN address',
            hintText: '192.168.31.250:3478',
            border: OutlineInputBorder(),
          )),
          const SizedBox(height: 8),
          TextField(controller: _turnUserCtrl, decoration: const InputDecoration(
            labelText: 'TURN username',
            hintText: 'huginn',
            border: OutlineInputBorder(),
          )),
          const SizedBox(height: 8),
          TextField(controller: _turnPassCtrl, decoration: const InputDecoration(
            labelText: 'TURN password',
            hintText: 'changeme',
            border: OutlineInputBorder(),
          )),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Save')),
        ],
      ),
    );
  }
}
