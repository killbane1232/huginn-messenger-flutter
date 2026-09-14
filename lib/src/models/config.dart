class AppConfig {
  String username;
  String muninnAddr;
  String chunkTtl;
  String dbPath;
  String turnAddr;
  String turnUser;
  String turnPass;

  AppConfig({
    this.username = '',
    this.muninnAddr = '',
    this.chunkTtl = '1w',
    this.dbPath = 'huginn.db',
    this.turnAddr = '',
    this.turnUser = '',
    this.turnPass = '',
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    username: json['username'] as String? ?? '',
    muninnAddr: json['muninn'] as String? ?? '',
    chunkTtl: json['chunk_ttl'] as String? ?? '1w',
    dbPath: json['db_path'] as String? ?? 'huginn.db',
    turnAddr: json['turn_addr'] as String? ?? '',
    turnUser: json['turn_user'] as String? ?? '',
    turnPass: json['turn_pass'] as String? ?? '',
  );

  static bool isValidMuninnAddr(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  Map<String, dynamic> toJson() => {
    'username': username,
    'muninn': muninnAddr,
    'chunk_ttl': chunkTtl,
    'turn_addr': turnAddr,
    'turn_user': turnUser,
    'turn_pass': turnPass,
  };
}
