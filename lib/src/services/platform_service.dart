import 'dart:io';
import 'package:flutter/services.dart';
import 'messenger_service.dart';

class PlatformService {
  static const _androidChannel = MethodChannel(
    'com.example.huginn_messenger/background',
  );
  static const _platformChannel = MethodChannel(
    'com.example.huginn_messenger/platform',
  );
  static bool _initialized = false;

  static Future<void> init(MessengerService service) async {
    if (_initialized) return;
    _initialized = true;

    if (Platform.isAndroid) {
      if (!await hasAllFilesAccess()) {
        await requestAllFilesAccess();
      }
      await _startAndroidService();
      await _setupAndroidDownloads(service);
    }
  }

  static Future<void> dispose() async {
    if (!_initialized) return;
    if (Platform.isAndroid) {
      await _stopAndroidService();
    }
    _initialized = false;
  }

  static Future<void> _startAndroidService() async {
    try {
      await _androidChannel.invokeMethod('startService');
    } catch (_) {}
  }

  static Future<void> _stopAndroidService() async {
    try {
      await _androidChannel.invokeMethod('stopService');
    } catch (_) {}
  }

  static Future<void> _setupAndroidDownloads(MessengerService service) async {
    try {
      final dir = await _platformChannel.invokeMethod<String>(
        'getDownloadsDir',
      );
      if (dir != null && dir.isNotEmpty) {
        service.setDownloadsDir(dir);
      }
    } catch (_) {}
  }

  static Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _platformChannel.invokeMethod<bool>(
        'hasAllFilesAccess',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestAllFilesAccess() async {
    if (!Platform.isAndroid) return;
    try {
      await _platformChannel.invokeMethod('requestAllFilesAccess');
    } catch (_) {}
  }

  static Future<void> openNotificationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _platformChannel.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  static Future<bool> openFile(String path) async {
    try {
      if (Platform.isAndroid) {
        final result = await _platformChannel.invokeMethod<bool>('openFile', {
          'path': path,
        });
        return result ?? false;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [
          path,
        ], mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [path], mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [
          path,
        ], mode: ProcessStartMode.detached);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
