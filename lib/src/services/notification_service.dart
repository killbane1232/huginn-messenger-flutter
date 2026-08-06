import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

class NotificationService {
  static const _notificationIcon = 'ic_notification';
  static const _fallbackNotificationIcon = 'ic_launcher_background';
  static const _messagesChannel = AndroidNotificationChannel(
    'huginn_messages',
    'Messages',
    description: 'New message notifications',
    importance: Importance.high,
  );

  static FlutterLocalNotificationsPlugin? _androidPlugin;
  static bool _initialized = false;
  static bool _notificationsEnabled = true;
  static String _activeNotificationIcon = _notificationIcon;

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
    try {
      await _initializeAndroidPlugin(_notificationIcon, onNotificationTap);
    } on PlatformException catch (error) {
      if (error.code != 'invalid_icon') rethrow;
      _activeNotificationIcon = _fallbackNotificationIcon;
      await _initializeAndroidPlugin(
        _fallbackNotificationIcon,
        onNotificationTap,
      );
    }

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

  static Future<void> _initializeAndroidPlugin(
    String icon,
    void Function(String chatId) onNotificationTap,
  ) async {
    final settings = InitializationSettings(
      android: AndroidInitializationSettings(icon),
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
    final androidDetails = AndroidNotificationDetails(
      'huginn_messages',
      'Messages',
      channelDescription: 'New message notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: _activeNotificationIcon,
    );
    await _androidPlugin!.show(
      id: chatId.hashCode,
      title: peerName,
      body: text,
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: chatId,
    );
  }

  static Future<void> _showLinux(String title, String body) async {
    try {
      await Process.run('notify-send', [title, body]);
    } catch (_) {}
  }
}
