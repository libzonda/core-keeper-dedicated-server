class ServerStatus {
  final String status;
  final int pid;
  final int uptimeSec;
  final String gameId;
  final String networkMode;
  final int port;
  final int activeWorld;
  final int maxPlayers;
  final String serverName;
  final String instanceId;
  final String instanceName;
  final String worldName;
  final bool restartRequired;
  final String version;

  ServerStatus({
    required this.status,
    required this.pid,
    required this.uptimeSec,
    required this.gameId,
    required this.networkMode,
    required this.port,
    required this.activeWorld,
    required this.maxPlayers,
    required this.serverName,
    this.instanceId = '',
    this.instanceName = '',
    this.worldName = '',
    this.restartRequired = false,
    this.version = '',
  });

  bool get isRunning => status == 'running';
  bool get isStarting => status == 'starting';
  bool get isStopped => status == 'stopped';
  bool get isStopping => status == 'stopping';
  bool get isUpdating => status == 'updating';
  bool get isSDR => networkMode.toLowerCase() == 'sdr';

  String get formattedUptime {
    if (uptimeSec <= 0) return '0s';
    final d = uptimeSec ~/ 86400;
    final h = (uptimeSec % 86400) ~/ 3600;
    final m = (uptimeSec % 3600) ~/ 60;
    final s = uptimeSec % 60;
    if (d > 0) return '${d}d ${h}h ${m}m';
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  factory ServerStatus.fromJson(Map<String, dynamic> json) {
    return ServerStatus(
      status: json['status'] ?? 'stopped',
      pid: json['pid'] ?? 0,
      uptimeSec: (json['uptimeSec'] as num?)?.toInt() ?? 0,
      gameId: json['gameId'] ?? '',
      networkMode: json['networkMode'] ?? 'sdr',
      port: json['port'] ?? 27015,
      activeWorld: json['activeWorld'] ?? 0,
      maxPlayers: json['maxPlayers'] ?? 10,
      serverName: json['serverName'] ?? '',
      instanceId: json['instanceId'] ?? '',
      instanceName: json['instanceName'] ?? '',
      worldName: json['worldName'] ?? '',
      restartRequired: json['restartRequired'] == true,
      version: json['version'] ?? '',
    );
  }
}

