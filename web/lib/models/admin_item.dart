class AdminItem {
  final int index;
  final int privileges; // 2: Full Admin, 1: Moderator
  final String name;
  final String steamId;

  AdminItem({
    required this.index,
    required this.privileges,
    required this.name,
    required this.steamId,
  });

  bool get isFullAdmin => privileges >= 2;

  factory AdminItem.fromJson(Map<String, dynamic> json) {
    String sId = '';
    if (json['steamIdStr'] != null) {
      sId = json['steamIdStr'].toString();
    } else if (json['steamId'] != null) {
      sId = json['steamId'].toString();
    }
    return AdminItem(
      index: json['index'] ?? 0,
      privileges: json['privileges'] ?? 2,
      name: json['name'] ?? '',
      steamId: sId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'privileges': privileges,
      'name': name,
      'steamId': steamId,
      'steamIdStr': steamId,
    };
  }
}

