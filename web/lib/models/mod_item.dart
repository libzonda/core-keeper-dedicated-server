class ModItem {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final bool enabled;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final bool isWorkshop;
  final String workshopId;
  final String source;
  final String sourceUrl;
  final bool canUpdate;

  ModItem({
    required this.id,
    required this.name,
    this.version = '',
    this.author = '',
    this.description = '',
    required this.enabled,
    required this.sizeBytes,
    this.modifiedAt,
    required this.isWorkshop,
    required this.workshopId,
    this.source = 'upload',
    this.sourceUrl = '',
    this.canUpdate = false,
  });

  String get formattedSize {
    if (sizeBytes <= 0) return '0 KB';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  factory ModItem.fromJson(Map<String, dynamic> json) {
    return ModItem(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      version: json['version'] ?? '',
      author: json['author'] ?? '',
      description: json['description'] ?? '',
      enabled: json['enabled'] ?? true,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.tryParse(json['modifiedAt'])
          : null,
      isWorkshop: json['isWorkshop'] ?? false,
      workshopId: json['workshopId'] ?? '',
      source: json['source'] ?? (json['isWorkshop'] == true ? 'workshop' : 'upload'),
      sourceUrl: json['sourceUrl'] ?? '',
      canUpdate: json['canUpdate'] ?? false,
    );
  }
}

