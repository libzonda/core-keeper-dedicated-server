class WorldItem {
  final int index;
  final String name;
  final bool exists;
  final int sizeBytes;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final bool isActive;
  final int mode;
  final int seed;

  WorldItem({
    required this.index,
    required this.name,
    required this.exists,
    required this.sizeBytes,
    this.createdAt,
    this.modifiedAt,
    required this.isActive,
    this.mode = 0,
    this.seed = 0,
  });

  String formattedSizeWith([String fallback = '']) {
    if (!exists || sizeBytes <= 0) return fallback;
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedSize => formattedSizeWith();

  String get formattedCreatedAt {
    if (createdAt == null || createdAt!.year <= 1) return '';
    final local = createdAt!.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  factory WorldItem.fromJson(Map<String, dynamic> json) {
    return WorldItem(
      index: json['index'] ?? 0,
      name: json['name'] ?? '',
      exists: json['exists'] ?? false,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.tryParse(json['modifiedAt'])
          : null,
      isActive: json['isActive'] ?? false,
      mode: json['mode'] ?? 0,
      seed: (json['seed'] as num?)?.toInt() ?? 0,
    );
  }
}

