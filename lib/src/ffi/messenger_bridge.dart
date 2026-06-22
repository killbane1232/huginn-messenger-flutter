import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

DynamicLibrary _load() {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('huginn_messenger.framework/huginn_messenger');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libhuginn_messenger.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('huginn_messenger.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

final DynamicLibrary _lib = _load();

typedef _CreateNative = Int64 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _CreateDart = int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef _TwoStrNative = Pointer<Utf8> Function(Int64, Pointer<Utf8>);
typedef _TwoStrDart = Pointer<Utf8> Function(int, Pointer<Utf8>);

typedef _ThreeStrNative = Pointer<Utf8> Function(Int64, Pointer<Utf8>, Pointer<Utf8>);
typedef _ThreeStrDart = Pointer<Utf8> Function(int, Pointer<Utf8>, Pointer<Utf8>);

typedef _DestroyNative = Void Function(Int64);
typedef _DestroyDart = void Function(int);

typedef _StrFnNative = Pointer<Utf8> Function(Int64);
typedef _StrFnDart = Pointer<Utf8> Function(int);

typedef _StrStrNative = Pointer<Utf8> Function(Int64, Pointer<Utf8>);
typedef _StrStrDart = Pointer<Utf8> Function(int, Pointer<Utf8>);

typedef _SendNative = Pointer<Utf8> Function(Int64, Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _SendDart = Pointer<Utf8> Function(int, Pointer<Utf8>, Pointer<Utf8>, int);

typedef _SendFileNative = Pointer<Utf8> Function(Int64, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _SendFileDart = Pointer<Utf8> Function(int, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);

typedef _ConfigSaveNative = Pointer<Utf8> Function(Int64, Pointer<Utf8>);
typedef _ConfigSaveDart = Pointer<Utf8> Function(int, Pointer<Utf8>);

typedef _EventNative = Pointer<Utf8> Function(Int64, Int32);
typedef _EventDart = Pointer<Utf8> Function(int, int);

typedef _OnlineNative = Int32 Function(Int64, Pointer<Utf8>);
typedef _OnlineDart = int Function(int, Pointer<Utf8>);

typedef _FreeStrNative = Void Function(Pointer<Utf8>);
typedef _FreeStrDart = void Function(Pointer<Utf8>);

final _create = _lib.lookupFunction<_CreateNative, _CreateDart>('messenger_create');
final _destroy = _lib.lookupFunction<_DestroyNative, _DestroyDart>('messenger_destroy');
final _getMe = _lib.lookupFunction<_StrFnNative, _StrFnDart>('messenger_get_me');
final _getPeers = _lib.lookupFunction<_StrFnNative, _StrFnDart>('messenger_get_peers');
final _searchPeers = _lib.lookupFunction<_StrStrNative, _StrStrDart>('messenger_search_peers');
final _getMessages = _lib.lookupFunction<_StrStrNative, _StrStrDart>('messenger_get_messages');
final _sendMessage = _lib.lookupFunction<_SendNative, _SendDart>('messenger_send_message');
final _sendFile = _lib.lookupFunction<_SendFileNative, _SendFileDart>('messenger_send_file');
final _getConfig = _lib.lookupFunction<_StrFnNative, _StrFnDart>('messenger_get_config');
final _saveConfig = _lib.lookupFunction<_ConfigSaveNative, _ConfigSaveDart>('messenger_save_config');
final _getEvent = _lib.lookupFunction<_EventNative, _EventDart>('messenger_get_event');
final _isOnline = _lib.lookupFunction<_OnlineNative, _OnlineDart>('messenger_is_peer_online');
final _freeStr = _lib.lookupFunction<_FreeStrNative, _FreeStrDart>('messenger_free_string');
final _createGroup = _lib.lookupFunction<_TwoStrNative, _TwoStrDart>('messenger_create_group');
final _getGroups = _lib.lookupFunction<_StrFnNative, _StrFnDart>('messenger_get_groups');
final _inviteToGroup = _lib.lookupFunction<_ThreeStrNative, _ThreeStrDart>('messenger_invite_to_group');
final _genRelogin = _lib.lookupFunction<_StrFnNative, _StrFnDart>('messenger_generate_relogin_signature');
final _applyRelogin = _lib.lookupFunction<_ConfigSaveNative, _ConfigSaveDart>('messenger_apply_relogin_signature');

String _readAndFree(Pointer<Utf8> ptr) {
  final s = ptr.toDartString();
  _freeStr(ptr);
  return s;
}

int messengerCreate(String username, String muninnAddr, String dbPath, String chunkTtl,
    {String turnAddr = '', String turnUser = '', String turnPass = ''}) {
  final u = username.toNativeUtf8();
  final m = muninnAddr.toNativeUtf8();
  final d = dbPath.toNativeUtf8();
  final c = chunkTtl.toNativeUtf8();
  final ta = turnAddr.toNativeUtf8();
  final tu = turnUser.toNativeUtf8();
  final tp = turnPass.toNativeUtf8();
  final handle = _create(u, m, d, c, ta, tu, tp);
  calloc.free(u);
  calloc.free(m);
  calloc.free(d);
  calloc.free(c);
  calloc.free(ta);
  calloc.free(tu);
  calloc.free(tp);
  return handle;
}

void messengerDestroy(int handle) => _destroy(handle);

String messengerGetMe(int handle) => _readAndFree(_getMe(handle));

String messengerGetPeers(int handle) => _readAndFree(_getPeers(handle));

String messengerSearchPeers(int handle, String query) {
  final q = query.toNativeUtf8();
  final r = _readAndFree(_searchPeers(handle, q));
  calloc.free(q);
  return r;
}

String messengerGetMessages(int handle, String peerId) {
  final p = peerId.toNativeUtf8();
  final r = _readAndFree(_getMessages(handle, p));
  calloc.free(p);
  return r;
}

String messengerSendMessage(int handle, String to, String text, int ttl) {
  final t = to.toNativeUtf8();
  final x = text.toNativeUtf8();
  final r = _readAndFree(_sendMessage(handle, t, x, ttl));
  calloc.free(t);
  calloc.free(x);
  return r;
}

String messengerSendFile(int handle, String to, String text, String filePath, int ttl) {
  final t = to.toNativeUtf8();
  final x = text.toNativeUtf8();
  final f = filePath.toNativeUtf8();
  final r = _readAndFree(_sendFile(handle, t, x, f, ttl));
  calloc.free(t);
  calloc.free(x);
  calloc.free(f);
  return r;
}

String messengerGetConfig(int handle) => _readAndFree(_getConfig(handle));

String messengerSaveConfig(int handle, String json) {
  final j = json.toNativeUtf8();
  final r = _readAndFree(_saveConfig(handle, j));
  calloc.free(j);
  return r;
}

String messengerGetEvent(int handle, int timeoutMs) => _readAndFree(_getEvent(handle, timeoutMs));

bool messengerIsPeerOnline(int handle, String peerId) {
  final p = peerId.toNativeUtf8();
  final r = _isOnline(handle, p) != 0;
  calloc.free(p);
  return r;
}

String messengerCreateGroup(int handle, String name) {
  final n = name.toNativeUtf8();
  final r = _readAndFree(_createGroup(handle, n));
  calloc.free(n);
  return r;
}

String messengerGetGroups(int handle) => _readAndFree(_getGroups(handle));

String messengerInviteToGroup(int handle, String groupUid, String userId) {
  final g = groupUid.toNativeUtf8();
  final u = userId.toNativeUtf8();
  final r = _readAndFree(_inviteToGroup(handle, g, u));
  calloc.free(g);
  calloc.free(u);
  return r;
}

String messengerGenerateReloginSignature(int handle) => _readAndFree(_genRelogin(handle));

String messengerApplyReloginSignature(int handle, String signature) {
  final s = signature.toNativeUtf8();
  final r = _readAndFree(_applyRelogin(handle, s));
  calloc.free(s);
  return r;
}
