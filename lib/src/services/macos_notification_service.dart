import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class MacOSNotificationService {
  final _plugin = MacOSFlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _notificationsEnabled = false;

  bool get notificationsEnabled => _notificationsEnabled;

  Future<String?> init({
    required void Function(String chatId) onNotificationTap,
  }) async {
    await _plugin.initialize(
      settings: const DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
        defaultPresentBadge: false,
      ),
      onDidReceiveNotificationResponse: (response) {
        final chatId = response.payload?.trim();
        if (chatId != null && chatId.isNotEmpty) onNotificationTap(chatId);
      },
    );
    _ready = true;
    _notificationsEnabled =
        (await _plugin.checkPermissions())?.isEnabled ?? false;
    if (!_notificationsEnabled) {
      _notificationsEnabled =
          await _plugin.requestPermissions(alert: true, sound: true) ?? false;
    }

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final chatId = launchDetails?.notificationResponse?.payload?.trim();
      if (chatId != null && chatId.isNotEmpty) return chatId;
    }
    return null;
  }

  Future<void> showMessage({
    required String chatId,
    required String peerName,
    required String text,
  }) async {
    if (!_ready) return;
    // Reflect changes made in System Settings without restarting the app.
    _notificationsEnabled =
        (await _plugin.checkPermissions())?.isEnabled ?? false;
    if (!_notificationsEnabled) return;

    await _plugin.show(
      id: chatId.hashCode & 0x7fffffff,
      title: peerName,
      body: text,
      payload: chatId,
      notificationDetails: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
        presentBadge: false,
        threadIdentifier: chatId,
      ),
    );
  }

  Future<bool?> openSettings() => _plugin.openAppNotificationSettings();
}
