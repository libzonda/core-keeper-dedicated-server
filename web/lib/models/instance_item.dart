class InstanceItem {
	final String id;
	final String name;
	final int port;
	final String networkMode;
	final String password;
	final int worldIndex;
	final String worldName;
	final int worldSeed;
	final int worldMode;
	final int maxPlayers;
	final bool autoStart;
	final List<String> enabledMods;
	final DateTime createdAt;
	final String status; // "running", "stopped", "starting", "stopping", "updating"
	final int pid;
	final int uptimeSec;
	final String gameId;
	final int enabledModsCount;
	final int totalModsCount;
	final bool isActive;
	final bool restartRequired;

	InstanceItem({
		required this.id,
		required this.name,
		required this.port,
		required this.networkMode,
		required this.password,
		required this.worldIndex,
		required this.worldName,
		required this.worldSeed,
		required this.worldMode,
		required this.maxPlayers,
		required this.autoStart,
		required this.enabledMods,
		required this.createdAt,
		required this.status,
		required this.pid,
		required this.uptimeSec,
		required this.gameId,
		required this.enabledModsCount,
		required this.totalModsCount,
		required this.isActive,
		required this.restartRequired,
	});

	bool get isRunning => status == 'running';
	bool get isStarting => status == 'starting';
	bool get isStopped => status == 'stopped';
	bool get isStopping => status == 'stopping';
	bool get isUpdating => status == 'updating';

	String get formattedUptime {
		if (uptimeSec <= 0) return '0s';
		final days = uptimeSec ~/ 86400;
		final hours = (uptimeSec % 86400) ~/ 3600;
		final minutes = (uptimeSec % 3600) ~/ 60;
		final seconds = uptimeSec % 60;

		if (days > 0) return '${days}d ${hours}h';
		if (hours > 0) return '${hours}h ${minutes}m';
		if (minutes > 0) return '${minutes}m ${seconds}s';
		return '${seconds}s';
	}

	factory InstanceItem.fromJson(Map<String, dynamic> json) {
		return InstanceItem(
			id: json['id'] as String? ?? 'default',
			name: json['name'] as String? ?? 'Default Server',
			port: (json['port'] as num?)?.toInt() ?? 27015,
			networkMode: json['networkMode'] as String? ?? 'sdr',
			password: json['password'] as String? ?? '',
			worldIndex: (json['worldIndex'] as num?)?.toInt() ?? 0,
			worldName: json['worldName'] as String? ?? '',
			worldSeed: (json['worldSeed'] as num?)?.toInt() ?? 0,
			worldMode: (json['worldMode'] as num?)?.toInt() ?? 0,
			maxPlayers: (json['maxPlayers'] as num?)?.toInt() ?? 10,
			autoStart: json['autoStart'] as bool? ?? true,
			enabledMods: (json['enabledMods'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
			createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now() : DateTime.now(),
			status: json['status'] as String? ?? 'stopped',
			pid: (json['pid'] as num?)?.toInt() ?? 0,
			uptimeSec: (json['uptimeSec'] as num?)?.toInt() ?? 0,
			gameId: json['gameId'] as String? ?? '',
			enabledModsCount: (json['enabledModsCount'] as num?)?.toInt() ?? 0,
			totalModsCount: (json['totalModsCount'] as num?)?.toInt() ?? 0,
			isActive: json['isActive'] as bool? ?? false,
			restartRequired: json['restartRequired'] as bool? ?? false,
		);
	}
}
