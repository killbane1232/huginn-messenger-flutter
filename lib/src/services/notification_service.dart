import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static const _messagesChannel = AndroidNotificationChannel(
    'huginn_messages',
    'Messages',
    description: 'New message notifications',
    importance: Importance.high,
  );

  static FlutterLocalNotificationsPlugin? _androidPlugin;
  static bool _initialized = false;
  static bool _notificationsEnabled = true;

  static bool get notificationsEnabled => _notificationsEnabled;

  static Future<String?> init({
    required void Function(String chatId) onNotificationTap,
  }) async {
    if (_initialized) return null;
    _initialized = true;

    if (Platform.isAndroid) {
      return _initAndroid(onNotificationTap);
    }
    return null;
  }

  static Future<String?> _initAndroid(
    void Function(String chatId) onNotificationTap,
  ) async {
    _androidPlugin = FlutterLocalNotificationsPlugin();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
    );
    await _androidPlugin!.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final chatId = response.payload?.trim();
        if (chatId != null && chatId.isNotEmpty) {
          onNotificationTap(chatId);
        }
      },
    );

    final android = _androidPlugin!
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.createNotificationChannel(_messagesChannel);
      var enabled = await android.areNotificationsEnabled() ?? false;
      if (!enabled) {
        enabled = await android.requestNotificationsPermission() ?? false;
      }

      final channels = await android.getNotificationChannels() ?? [];
      final messageChannels = channels.where(
        (channel) => channel.id == _messagesChannel.id,
      );
      final channelEnabled =
          messageChannels.isEmpty ||
          messageChannels.first.importance != Importance.none;
      _notificationsEnabled = enabled && channelEnabled;
    }

    final launchDetails = await _androidPlugin!
        .getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final chatId = launchDetails?.notificationResponse?.payload?.trim();
      if (chatId != null && chatId.isNotEmpty) return chatId;
    }
    return null;
  }

  static Future<void> showMessageNotification({
    required String chatId,
    required String peerName,
    required String text,
  }) async {
    if (Platform.isAndroid) {
      await _showAndroid(chatId, peerName, text);
    } else if (Platform.isLinux) {
      await _showLinux(peerName, text);
    }
  }

  static Future<void> _showAndroid(
    String chatId,
    String peerName,
    String text,
  ) async {
    if (_androidPlugin == null) {
      throw StateError('Android notifications are not initialized');
    }
    const androidDetails = AndroidNotificationDetails(
      'huginn_messages',
      'Messages',
      channelDescription: 'New message notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
    );
    await _androidPlugin!.show(
      id: chatId.hashCode,
      title: peerName,
      body: text,
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: chatId,
    );
  }

  static Future<void> _showLinux(String title, String body) async {
    try {
      await Process.run('notify-send', [title, body]);
    } catch (_) {}
  }
}
