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
  bool proxyDiscord;
  String proxyType; // "http", "socks5", "clash"
  String proxyAddress;
  String clashApiUrl;
  String clashSecret;
  String clashNode;
  String clashGroup;

  DiscordConfig discord;

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
    this.proxyDiscord = true,
    this.proxyType = 'http',
    this.proxyAddress = '',
    this.clashApiUrl = 'http://127.0.0.1:9090',
    this.clashSecret = '',
    this.clashNode = '',
    this.clashGroup = '',
    DiscordConfig? discord,
  }) : discord = discord ?? DiscordConfig();

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
      proxyDiscord: json['proxyDiscord'] ?? true,
      proxyType: json['proxyType'] ?? 'http',
      proxyAddress: json['proxyAddress'] ?? '',
      clashApiUrl: json['clashApiUrl'] ?? 'http://127.0.0.1:9090',
      clashSecret: json['clashSecret'] ?? '',
      clashNode: json['clashNode'] ?? '',
      clashGroup: json['clashGroup'] ?? '',
      discord: json['discord'] != null ? DiscordConfig.fromJson(json['discord']) : DiscordConfig(),
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
      'proxyDiscord': proxyDiscord,
      'proxyType': proxyType,
      'proxyAddress': proxyAddress,
      'clashApiUrl': clashApiUrl,
      'clashSecret': clashSecret,
      'clashNode': clashNode,
      'clashGroup': clashGroup,
      'discord': discord.toJson(),
    };
  }
}

class DiscordMessageTemplate {
  bool enabled;
  String color; // Hex string e.g. "#2ECC71"
  String title;
  String description;

  DiscordMessageTemplate({
    required this.enabled,
    required this.color,
    required this.title,
    required this.description,
  });

  factory DiscordMessageTemplate.fromJson(Map<String, dynamic> json) {
    return DiscordMessageTemplate(
      enabled: json['enabled'] ?? true,
      color: json['color'] ?? '#2ECC71',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'color': color,
      'title': title,
      'description': description,
    };
  }

  DiscordMessageTemplate copyWith({
    bool? enabled,
    String? color,
    String? title,
    String? description,
  }) {
    return DiscordMessageTemplate(
      enabled: enabled ?? this.enabled,
      color: color ?? this.color,
      title: title ?? this.title,
      description: description ?? this.description,
    );
  }
}

class DiscordConfig {
  bool enabled;
  String webhookUrl;
  String botName;
  String avatarUrl;
  Map<String, DiscordMessageTemplate> messages;

  DiscordConfig({
    this.enabled = false,
    this.webhookUrl = '',
    this.botName = 'Core Keeper Bot',
    this.avatarUrl = 'https://raw.githubusercontent.com/libzonda/core-keeper-dedicated-server/main/logo.png',
    Map<String, DiscordMessageTemplate>? messages,
  }) : messages = messages ?? defaultMessages();

  static Map<String, DiscordMessageTemplate> defaultMessages() {
    return {
      'server_online': DiscordMessageTemplate(
        enabled: true,
        color: '#2ECC71',
        title: '🟢 {server_name} Server is Ready',
        description: 'Core Keeper Dedicated Server is running and ready for players to join!\n• **Game ID**: `{game_id}`\n• **Network Mode**: {network_mode}\n• **World**: {world_name} (Slot {world_index})\n• **Max Players**: {max_players}',
      ),
      'server_offline': DiscordMessageTemplate(
        enabled: true,
        color: '#95A5A6',
        title: '⚪ {server_name} Server Stopped',
        description: 'The server has shut down gracefully.\n• **Uptime**: {uptime}',
      ),
      'server_crashed': DiscordMessageTemplate(
        enabled: true,
        color: '#E74C3C',
        title: '🔴 {server_name} Server Crashed',
        description: '⚠️ Dedicated server process exited unexpectedly!\n• **Exit Code**: {exit_code}\n• **Error Log Summary**:\n```\n{error_log}\n```',
      ),
      'player_join': DiscordMessageTemplate(
        enabled: true,
        color: '#3498DB',
        title: '🎮 Player Joined the Underground World',
        description: 'Player **{player_name}** has joined the server.',
      ),
      'player_leave': DiscordMessageTemplate(
        enabled: true,
        color: '#9B59B6',
        title: '👋 Player Left the Underground World',
        description: 'Player **{player_name}** has left the server.',
      ),
    };
  }

  factory DiscordConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return DiscordConfig();
    final msgs = <String, DiscordMessageTemplate>{};
    if (json['messages'] is Map) {
      (json['messages'] as Map).forEach((k, v) {
        if (v is Map<String, dynamic>) {
          msgs[k.toString()] = DiscordMessageTemplate.fromJson(v);
        } else if (v is Map) {
          msgs[k.toString()] = DiscordMessageTemplate.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }
    final defaults = defaultMessages();
    for (final entry in defaults.entries) {
      if (!msgs.containsKey(entry.key)) {
        msgs[entry.key] = entry.value;
      }
    }

    return DiscordConfig(
      enabled: json['enabled'] ?? false,
      webhookUrl: json['webhookUrl'] ?? '',
      botName: json['botName'] ?? 'Core Keeper Bot',
      avatarUrl: json['avatarUrl'] ?? 'https://raw.githubusercontent.com/libzonda/core-keeper-dedicated-server/main/logo.png',
      messages: msgs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'webhookUrl': webhookUrl,
      'botName': botName,
      'avatarUrl': avatarUrl,
      'messages': messages.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  DiscordConfig copyWith({
    bool? enabled,
    String? webhookUrl,
    String? botName,
    String? avatarUrl,
    Map<String, DiscordMessageTemplate>? messages,
  }) {
    return DiscordConfig(
      enabled: enabled ?? this.enabled,
      webhookUrl: webhookUrl ?? this.webhookUrl,
      botName: botName ?? this.botName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      messages: messages ?? Map.from(this.messages),
    );
  }
}
