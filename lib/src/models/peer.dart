class Peer {
  final String login;
  final String encryptionKey;
  final String signatureKey;
  final bool online;
  final DateTime lastSeen;

  Peer({
    required this.login,
    this.encryptionKey = '',
    this.signatureKey = '',
    this.online = false,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
    login: json['login'] as String? ?? '',
    encryptionKey: json['encryption_key'] as String? ?? '',
    signatureKey: json['signature_key'] as String? ?? '',
    online: json['online'] as bool? ?? false,
    lastSeen: json['last_seen'] != null
        ? DateTime.tryParse(json['last_seen'] as String) ??
              DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'login': login,
    'online': online,
    'last_seen': lastSeen.toIso8601String(),
  };

  String get displayLogin {
    final value = login.trim();
    final signatureSuffix = signatureKey.isEmpty ? '' : ':$signatureKey';
    if (signatureSuffix.isNotEmpty && value.endsWith(signatureSuffix)) {
      return value.substring(0, value.length - signatureSuffix.length);
    }

    final separator = value.indexOf(':');
    return separator > 0 ? value.substring(0, separator) : value;
  }

  String get key =>
      signatureKey.isEmpty ? displayLogin : '$displayLogin:$signatureKey';
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Peer && key == other.key;
  @override
  int get hashCode => key.hashCode;
}
