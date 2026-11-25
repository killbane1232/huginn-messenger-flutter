import 'muninn_ice_config.dart';

class AppConfig {
  String username;
  String muninnAddr;
  List<String> muninnServers;
  Map<String, MuninnIceConfig> muninnIce;
  String chunkTtl;
  String dbPath;

  AppConfig({
    this.username = '',
    this.muninnAddr = '',
    List<String> muninnServers = const [],
    Map<String, MuninnIceConfig> muninnIce = const {},
    this.chunkTtl = '1w',
    this.dbPath = 'huginn.db',
  }) : muninnServers = List.of(muninnServers),
       muninnIce = {
         for (final entry in muninnIce.entries)
           normalizeMuninnAddr(entry.key): entry.value,
       };

  MuninnIceConfig iceFor(String server) =>
      muninnIce[normalizeMuninnAddr(server)] ?? MuninnIceConfig();

  static const maxMuninnServers = 17;

  /// The selected server and all alternatives, without duplicates.
  List<String> get allMuninnServers => {
    if (muninnAddr.isNotEmpty) normalizeMuninnAddr(muninnAddr),
    ...muninnServers.map(normalizeMuninnAddr),
  }.toList();

  void setMuninnServers(Iterable<String> addresses) {
    final servers = addresses.map(normalizeMuninnAddr).toSet().toList();
    final current = normalizeMuninnAddr(muninnAddr);
    muninnAddr = servers.contains(current)
        ? current
        : servers.firstOrNull ?? '';
    muninnServers = servers.where((address) => address != muninnAddr).toList();
    muninnIce.removeWhere((address, _) => !servers.contains(address));
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    username: json['username'] as String? ?? '',
    muninnAddr: json['muninn'] as String? ?? '',
    muninnServers: (json['muninn_servers'] as List?)?.cast<String>() ?? [],
    muninnIce: (json['muninn_ice'] as Map<String, dynamic>? ?? {}).map(
      (server, value) => MapEntry(
        server,
        MuninnIceConfig.fromJson(value as Map<String, dynamic>),
      ),
    ),
    chunkTtl: json['chunk_ttl'] as String? ?? '1w',
    dbPath: json['db_path'] as String? ?? 'huginn.db',
  );

  static bool isValidMuninnAddr(String value) {
    try {
      final uri = Uri.parse(value.trim());
      return (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty &&
          !RegExp(r'[\s%]').hasMatch(uri.host) &&
          uri.userInfo.isEmpty &&
          !value.contains('@') &&
          uri.port > 0 &&
          uri.port <= 65535 &&
          (uri.path.isEmpty || uri.path == '/') &&
          !uri.hasQuery &&
          !uri.hasFragment;
    } on FormatException {
      return false;
    }
  }

  static String normalizeMuninnAddr(String value) {
    final trimmed = value.trim();
    if (!isValidMuninnAddr(trimmed)) return trimmed;
    final uri = Uri.parse(trimmed);
    return uri
        .replace(host: uri.host.replaceFirst(RegExp(r'\.$'), ''), path: '')
        .toString();
  }

  Map<String, dynamic> toJson() => {
    'username': username,
    'muninn': muninnAddr,
    'muninn_servers': muninnServers,
    'muninn_ice': muninnIce.map(
      (server, ice) => MapEntry(server, ice.toJson()),
    ),
    'chunk_ttl': chunkTtl,
  };
}
