class Peer {
  final String key;
  final String encryptionKey;
  final String signatureKey;
  final String? username;
  final bool online;
  final DateTime lastSeen;

  Peer({
    required this.key,
    this.encryptionKey = '',
    this.signatureKey = '',
    this.username,
    this.online = false,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
    key: json['key'] as String? ?? '',
    encryptionKey: json['encryption_key'] as String? ?? '',
    signatureKey: json['signature_key'] as String? ?? '',
    username: json['metadata'] is Map
        ? (json['metadata'] as Map)['username'] as String?
        : null,
    online: json['online'] as bool? ?? false,
    lastSeen: json['last_seen'] != null
        ? DateTime.tryParse(json['last_seen'] as String) ?? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'online': online,
    'last_seen': lastSeen.toIso8601String(),
  };

  @override
  bool operator ==(Object other) => identical(this, other) || other is Peer && key == other.key;
  @override
  int get hashCode => key.hashCode;
}
