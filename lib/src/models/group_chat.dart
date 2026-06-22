class GroupChat {
  final String uid;
  final String name;
  final DateTime createdAt;

  GroupChat({
    required this.uid,
    required this.name,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory GroupChat.fromJson(Map<String, dynamic> json) => GroupChat(
    uid: json['uid'] as String? ?? '',
    name: json['name'] as String? ?? '',
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
        : DateTime.now(),
  );
}
