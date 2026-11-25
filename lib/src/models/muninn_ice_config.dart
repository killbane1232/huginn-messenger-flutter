import 'package:flutter/foundation.dart';

class MuninnIceConfig {
  final List<String> stunUrls;
  final List<String> turnUrls;
  final String turnUsername;
  final String turnPassword;

  MuninnIceConfig({
    List<String> stunUrls = const [],
    List<String> turnUrls = const [],
    this.turnUsername = '',
    this.turnPassword = '',
  }) : stunUrls = List.unmodifiable(stunUrls),
       turnUrls = List.unmodifiable(turnUrls);

  factory MuninnIceConfig.fromJson(Map<String, dynamic> json) =>
      MuninnIceConfig(
        stunUrls: (json['stun_urls'] as List?)?.cast<String>() ?? [],
        turnUrls: (json['turn_urls'] as List?)?.cast<String>() ?? [],
        turnUsername: json['turn_username'] as String? ?? '',
        turnPassword: json['turn_password'] as String? ?? '',
      );

  static bool isValidUrl(String value, {required bool turn}) {
    final match = RegExp(
      r'^(stun|stuns|turn|turns):(\[[^\]]+\]|[^:/?#@\s]+)(?::([0-9]+))?(?:\?transport=(udp|tcp))?$',
    ).firstMatch(value.trim());
    if (match == null || match[1]!.startsWith('turn') != turn) return false;
    if (!turn && match[4] != null) return false;
    final port = match[3] == null ? 3478 : int.tryParse(match[3]!);
    if (port == null || port < 1 || port > 65535) return false;
    final host = Uri.tryParse('http://${match[2]}');
    return host != null && host.host.isNotEmpty && !host.host.contains('%');
  }

  String? get validationError {
    if (!stunUrls.every((url) => isValidUrl(url, turn: false))) {
      return 'Use stun:host:port or stuns:host:port, one URL per line';
    }
    if (!turnUrls.every((url) => isValidUrl(url, turn: true))) {
      return 'Use turn:host:port or turns:host:port; transport may be udp or tcp';
    }
    if (turnUrls.isNotEmpty &&
        (turnUsername.trim().isEmpty || turnPassword.isEmpty)) {
      return 'TURN requires a username and password';
    }
    return null;
  }

  MuninnIceConfig normalized() => MuninnIceConfig(
    stunUrls: stunUrls.map((url) => url.trim()).toSet().toList(),
    turnUrls: turnUrls.map((url) => url.trim()).toSet().toList(),
    turnUsername: turnUrls.isEmpty ? '' : turnUsername.trim(),
    turnPassword: turnUrls.isEmpty ? '' : turnPassword,
  );

  bool sameSettingsAs(MuninnIceConfig other) =>
      listEquals(stunUrls, other.stunUrls) &&
      listEquals(turnUrls, other.turnUrls) &&
      turnUsername == other.turnUsername &&
      turnPassword == other.turnPassword;

  Map<String, dynamic> toJson() => {
    'stun_urls': stunUrls,
    'turn_urls': turnUrls,
    'turn_username': turnUsername,
    'turn_password': turnPassword,
  };
}
