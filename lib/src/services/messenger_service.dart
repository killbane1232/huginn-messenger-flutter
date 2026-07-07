import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import '../models/peer.dart';
import '../models/chat_message.dart';
import '../models/config.dart';
import '../models/app_event.dart';
import '../models/group_chat.dart';
import '../ffi/messenger_bridge.dart' as bridge;

const _uuid = Uuid();

class MessengerService {
  int _handle = 0;
  String? _currentUserId;
  String? _currentUsername;
  String? _dbPath;
  Timer? _pollTimer;
  final _eventCtrl = StreamController<AppEvent>.broadcast();
  final _peersCtrl = StreamController<List<Peer>>.broadcast();
  AppConfig _config = AppConfig();
  List<Peer> _lastPeers = [];
  final Map<String, String> _filePaths = {};

  bool get isReady => _handle > 0;
  String? get currentUserId => _currentUserId;
  String? get currentUsername => _currentUsername;
  Stream<AppEvent> get events => _eventCtrl.stream;
  Stream<List<Peer>> get peersStream => _peersCtrl.stream;
  AppConfig get config => _config;
  List<Peer> get peers => _lastPeers;
  Map<String, String> get filePaths => _filePaths;

  Future<GroupChat?> createGroup(String name) async {
    if (_handle <= 0) return null;
    final r = bridge.messengerCreateGroup(_handle, name);
    try {
      final data = jsonDecode(r) as Map<String, dynamic>;
      if (data.containsKey('error')) return null;
      return GroupChat.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  List<GroupChat> getGroups() {
    if (_handle <= 0) return [];
    final r = bridge.messengerGetGroups(_handle);
    try {
      return (jsonDecode(r) as List).map((e) => GroupChat.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  List<Peer> getPeers() {
    if (_handle <= 0) return [];
    final r = bridge.messengerGetPeers(_handle);
    try {
      return (jsonDecode(r) as List).map((e) => Peer.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  bool inviteToGroup(String groupUid, String userId) {
    if (_handle <= 0) return false;
    final r = bridge.messengerInviteToGroup(_handle, groupUid, userId);
    return r.contains('"ok"');
  }

  String? generateReloginSignature() {
    if (_handle <= 0) return null;
    final r = bridge.messengerGenerateReloginSignature(_handle);
    try {
      final data = jsonDecode(r) as Map<String, dynamic>;
      if (data.containsKey('error')) return null;
      return data['signature'] as String?;
    } catch (_) {
      return null;
    }
  }

  bool applyReloginSignature(String signature) {
    if (_handle <= 0) return false;
    final r = bridge.messengerApplyReloginSignature(_handle, signature);
    return r.contains('"ok"');
  }

  Future<bool> init({
    String? username,
    String muninnAddr = 'https://muninn.evil-bread.ru',
    String? dbPath,
    String chunkTtl = '1w',
    String turnAddr = '',
    String turnUser = '',
    String turnPass = '',
  }) async {
    if (isReady) return true;
    username ??= _uuid.v4();
    dbPath ??= await _defaultDbPath();
    _dbPath = dbPath;
    _handle = bridge.messengerCreate(username, muninnAddr, dbPath, chunkTtl,
        turnAddr: turnAddr, turnUser: turnUser, turnPass: turnPass);
    if (_handle <= 0) return false;
    _loadMe();
    _loadConfig();
    if (_config.username == username) {
      saveConfig(_config);
    }
    loadPeers();
    _startPolling();
    return true;
  }

  Future<String> _defaultDbPath() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/huginn.db';
    }
    return 'huginn.db';
  }

  void dispose() {
    _pollTimer?.cancel();
    if (_handle > 0) {
      bridge.messengerDestroy(_handle);
      _handle = 0;
    }
    _eventCtrl.close();
    _peersCtrl.close();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) => _poll());
  }

  void _poll() {
    if (_handle <= 0) return;
    final json = bridge.messengerGetEvent(_handle, 100);
    if (json.isEmpty) return;
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final type = data['type'] as String?;
      final raw = data['data'];
      if (type == 'peers' && raw != null) {
        final list = (raw as List).map((e) => Peer.fromJson(e as Map<String, dynamic>)).toList();
        _lastPeers = list;
        _peersCtrl.add(list);
        _eventCtrl.add(PeersEvent(list));
      } else if (type == 'message' && raw != null) {
        final msg = ChatMessage.fromJson(raw as Map<String, dynamic>);
        _eventCtrl.add(MessageEvent(msg));
      } else if (type == 'file_ready' && raw != null) {
        final m = raw as Map<String, dynamic>;
        final fileId = m['file_id'] as String? ?? '';
        final filePath = m['file_path'] as String? ?? '';
        final filename = m['filename'] as String? ?? '';
        final senderId = m['sender_id'] as String? ?? '';
        if (fileId.isNotEmpty && filePath.isNotEmpty) {
          _filePaths[fileId] = filePath;
          _eventCtrl.add(FileReadyEvent(
            fileId: fileId,
            filePath: filePath,
            filename: filename,
            senderId: senderId,
          ));
        }
      }
    } catch (_) {}
  }

  void _loadMe() {
    if (_handle <= 0) return;
    final json = bridge.messengerGetMe(_handle);
    if (json.isNotEmpty) {
      try {
        final data = jsonDecode(json) as Map<String, dynamic>;
        _currentUserId = data['id'] as String?;
        _currentUsername = data['username'] as String?;
      } catch (_) {}
    }
  }

  void _loadConfig() {
    if (_handle <= 0) return;
    final json = bridge.messengerGetConfig(_handle);
    if (json.isNotEmpty) {
      try {
        _config = AppConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  void loadPeers() {
    if (_handle <= 0) return;
    final json = bridge.messengerGetPeers(_handle);
    if (json.isNotEmpty) {
      try {
        _lastPeers = (jsonDecode(json) as List).map((e) => Peer.fromJson(e as Map<String, dynamic>)).toList();
        _peersCtrl.add(_lastPeers);
      } catch (_) {}
    }
  }

  void refreshPeers() => loadPeers();

  List<Peer> searchPeers(String query) {
    if (_handle <= 0) return [];
    final json = bridge.messengerSearchPeers(_handle, query);
    if (json.isEmpty) return [];
    try {
      return (jsonDecode(json) as List).map((e) => Peer.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ChatMessage>> getMessages(String peerId) async {
    if (_handle <= 0) return [];
    final json = bridge.messengerGetMessages(_handle, peerId);
    if (json.isEmpty) return [];
    try {
      return (jsonDecode(json) as List).map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ChatMessage>> getMessagesPaginated(String peerId, {int limit = 64, int offset = 0}) async {
    if (_handle <= 0) return [];
    final json = bridge.messengerGetMessagesPaginated(_handle, peerId, limit, offset);
    if (json.isEmpty) return [];
    try {
      final list = (jsonDecode(json) as List)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      return list.reversed.toList();
    } catch (_) {
      return [];
    }
  }

  bool sendMessage(String to, String text, {int ttl = 0}) {
    if (_handle <= 0) return false;
    final r = bridge.messengerSendMessage(_handle, to, text, ttl);
    return !r.contains('"error"');
  }

  bool sendFile(String to, String text, String filePath, {int ttl = 0}) {
    if (_handle <= 0) return false;
    final r = bridge.messengerSendFile(_handle, to, text, filePath, ttl);
    return !r.contains('"error"');
  }

  bool isOnline(String peerId) {
    if (_handle <= 0) return false;
    return bridge.messengerIsPeerOnline(_handle, peerId);
  }

  bool setDownloadsDir(String path) {
    if (_handle <= 0) return false;
    final r = bridge.messengerSetDownloadsDir(_handle, path);
    return r.contains('"ok"');
  }

  bool saveConfig(AppConfig newConfig) {
    if (_handle <= 0) return false;
    final r = bridge.messengerSaveConfig(_handle, jsonEncode(newConfig.toJson()));
    if (r.contains('"ok"')) {
      _config = newConfig;
      return true;
    }
    return false;
  }

  Future<bool> setUsername(String username) async {
    if (_handle <= 0 || _dbPath == null) return false;
    final newConfig = AppConfig(
      username: username,
      muninnAddr: _config.muninnAddr,
      chunkTtl: _config.chunkTtl,
      dbPath: _config.dbPath,
      turnAddr: _config.turnAddr,
      turnUser: _config.turnUser,
      turnPass: _config.turnPass,
    );
    if (!saveConfig(newConfig)) return false;
    _pollTimer?.cancel();
    bridge.messengerDestroy(_handle);
    _handle = bridge.messengerCreate(
      username, _config.muninnAddr, _dbPath!, _config.chunkTtl,
      turnAddr: _config.turnAddr,
      turnUser: _config.turnUser,
      turnPass: _config.turnPass,
    );
    if (_handle <= 0) return false;
    _currentUserId = null;
    _lastPeers = [];
    _filePaths.clear();
    _loadMe();
    _loadConfig();
    loadPeers();
    _startPolling();
    return true;
  }
}
