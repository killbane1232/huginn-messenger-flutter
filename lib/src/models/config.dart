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
    this.muninnAddr = 'https://muninn.evil-bread.ru',
    this.chunkTtl = '1w',
    this.dbPath = 'huginn.db',
    this.turnAddr = '',
    this.turnUser = '',
    this.turnPass = '',
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    username: json['username'] as String? ?? '',
    muninnAddr: json['muninn'] as String? ?? 'https://muninn.evil-bread.ru',
    chunkTtl: json['chunk_ttl'] as String? ?? '1w',
    dbPath: json['db_path'] as String? ?? 'huginn.db',
    turnAddr: json['turn_addr'] as String? ?? '',
    turnUser: json['turn_user'] as String? ?? '',
    turnPass: json['turn_pass'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'username': username,
    'muninn': muninnAddr,
    'chunk_ttl': chunkTtl,
    'turn_addr': turnAddr,
    'turn_user': turnUser,
    'turn_pass': turnPass,
  };
}
