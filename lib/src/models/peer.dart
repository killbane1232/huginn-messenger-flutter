class Peer {
  final String id;
  final String encryptionKey;
  final String signatureKey;
  final String? username;
  final bool online;
  final DateTime lastSeen;

  Peer({
    required this.id,
    this.encryptionKey = '',
    this.signatureKey = '',
    this.username,
    this.online = false,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
    id: json['id'] as String? ?? '',
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
    'id': id,
    'online': online,
    'last_seen': lastSeen.toIso8601String(),
  };

  @override
  bool operator ==(Object other) => identical(this, other) || other is Peer && id == other.id;
  @override
  int get hashCode => id.hashCode;
}
