class ServerConfig {
  String networkMode; // "sdr" or "direct"
  int port;
  String ip;
  String password;
  int worldIndex;
  String worldName;
  int worldSeed;
  int worldMode; // 0: Normal, 1: Hard, 2: Creative, 4: Casual
  int maxPlayers;
  String gameId;
  bool autoStart;
  bool autoUpdate;

  // Proxy settings
  bool proxyEnabled;
  bool proxySDR;
  bool proxySteamCmd;
  bool proxyMods;
  String proxyType; // "http", "socks5", "clash"
  String proxyAddress;
  String clashApiUrl;
  String clashSecret;
  String clashNode;
  String clashGroup;

  ServerConfig({
    required this.networkMode,
    required this.port,
    required this.ip,
    required this.password,
    required this.worldIndex,
    required this.worldName,
    required this.worldSeed,
    required this.worldMode,
    required this.maxPlayers,
    required this.gameId,
    required this.autoStart,
    required this.autoUpdate,
    this.proxyEnabled = false,
    this.proxySDR = true,
    this.proxySteamCmd = true,
    this.proxyMods = true,
    this.proxyType = 'http',
    this.proxyAddress = '',
    this.clashApiUrl = 'http://127.0.0.1:9090',
    this.clashSecret = '',
    this.clashNode = '',
    this.clashGroup = '',
  });

  bool get isSDR => networkMode.toLowerCase() == 'sdr';

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      networkMode: json['networkMode'] ?? 'sdr',
      port: json['port'] ?? 27015,
      ip: json['ip'] ?? '0.0.0.0',
      password: json['password'] ?? '',
      worldIndex: json['worldIndex'] ?? 0,
      worldName: json['worldName'] ?? "libzonda's Dedicated Server",
      worldSeed: (json['worldSeed'] as num?)?.toInt() ?? 0,
      worldMode: json['worldMode'] ?? 0,
      maxPlayers: json['maxPlayers'] ?? 10,
      gameId: json['gameId'] ?? '',
      autoStart: json['autoStart'] ?? true,
      autoUpdate: json['autoUpdate'] ?? true,
      proxyEnabled: json['proxyEnabled'] ?? false,
      proxySDR: json['proxySDR'] ?? true,
      proxySteamCmd: json['proxySteamCmd'] ?? true,
      proxyMods: json['proxyMods'] ?? true,
      proxyType: json['proxyType'] ?? 'http',
      proxyAddress: json['proxyAddress'] ?? '',
      clashApiUrl: json['clashApiUrl'] ?? 'http://127.0.0.1:9090',
      clashSecret: json['clashSecret'] ?? '',
      clashNode: json['clashNode'] ?? '',
      clashGroup: json['clashGroup'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'networkMode': networkMode,
      'port': port,
      'ip': ip,
      'password': password,
      'worldIndex': worldIndex,
      'worldName': worldName,
      'worldSeed': worldSeed,
      'worldMode': worldMode,
      'maxPlayers': maxPlayers,
      'gameId': gameId,
      'autoStart': autoStart,
      'autoUpdate': autoUpdate,
      'proxyEnabled': proxyEnabled,
      'proxySDR': proxySDR,
      'proxySteamCmd': proxySteamCmd,
      'proxyMods': proxyMods,
      'proxyType': proxyType,
      'proxyAddress': proxyAddress,
      'clashApiUrl': clashApiUrl,
      'clashSecret': clashSecret,
      'clashNode': clashNode,
      'clashGroup': clashGroup,
    };
  }
}
