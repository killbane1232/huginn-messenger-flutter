import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static FlutterLocalNotificationsPlugin? _androidPlugin;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (Platform.isAndroid) {
      await _initAndroid();
    }
  }

  static Future<void> _initAndroid() async {
    _androidPlugin = FlutterLocalNotificationsPlugin();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _androidPlugin!.initialize(settings);

    final android = _androidPlugin!
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestNotificationsPermission();
    }
  }

  static Future<void> showMessageNotification({
    required String peerId,
    required String peerName,
    required String text,
  }) async {
    if (Platform.isAndroid) {
      await _showAndroid(peerId, peerName, text);
    } else if (Platform.isLinux) {
      await _showLinux(peerName, text);
    }
  }

  static Future<void> _showAndroid(
    String peerId,
    String peerName,
    String text,
  ) async {
    if (_androidPlugin == null) return;
    const androidDetails = AndroidNotificationDetails(
      'huginn_messages',
      'Messages',
      channelDescription: 'New message notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );
    await _androidPlugin!.show(
      peerId.hashCode,
      peerName,
      text,
      const NotificationDetails(android: androidDetails),
      payload: peerId,
    );
  }

  static Future<void> _showLinux(String title, String body) async {
    try {
      await Process.run('notify-send', [title, body]);
    } catch (_) {}
  }
}
