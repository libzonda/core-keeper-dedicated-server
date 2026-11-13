import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/server_status.dart';
import '../models/server_config.dart';
import '../models/admin_item.dart';
import '../models/world_item.dart';
import '../models/mod_item.dart';
import '../models/instance_item.dart';
import '../utils/app_version.dart';

class ApiService {
  static final ApiService instance = ApiService._internal();
  ApiService._internal();

  String? currentInstanceId;
  String? currentInstanceName;
  final ValueNotifier<String?> activeInstanceNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<int?> tabNavigationNotifier = ValueNotifier<int?>(null);

  void navigateToTab(int index) {
    tabNavigationNotifier.value = index;
  }

  String _desktopBaseUrl = 'http://127.0.0.1:8080';

  Future<void> initDesktopSettings() async {
    if (!kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('desktop_server_url');
        if (saved != null && saved.trim().isNotEmpty) {
          _desktopBaseUrl = saved.trim().replaceAll(RegExp(r'/+$'), '');
        }
      } catch (_) {}
    }
  }

  Future<void> setDesktopBaseUrl(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    _desktopBaseUrl = clean.isNotEmpty ? clean : 'http://127.0.0.1:8080';
    if (!kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('desktop_server_url', _desktopBaseUrl);
      } catch (_) {}
    }
  }

  String get baseUrl {
    if (kIsWeb) {
      return '';
    }
    return _desktopBaseUrl;
  }

  String get wsUrl {
    if (kIsWeb) {
      final loc = Uri.base;
      final scheme = loc.scheme == 'https' ? 'wss' : 'ws';
      return '$scheme://${loc.host}:${loc.port}/api/ws/logs';
    }
    final parsed = Uri.tryParse(_desktopBaseUrl);
    final scheme = parsed?.scheme == 'https' ? 'wss' : 'ws';
    final host = (parsed?.host.isNotEmpty == true) ? parsed!.host : '127.0.0.1';
    final port = (parsed != null && parsed.hasPort) ? ':${parsed.port}' : (parsed?.scheme == 'https' ? '' : ':8080');
    return '$scheme://$host$port/api/ws/logs';
  }

  Uri _buildUri(String path, [Map<String, dynamic>? queryParams]) {
    final params = Map<String, dynamic>.from(queryParams ?? {});
    if (currentInstanceId != null && currentInstanceId!.isNotEmpty) {
      params['instance'] = currentInstanceId;
    }
    final urlStr = '$baseUrl$path';
    final baseUri = Uri.parse(urlStr);
    return baseUri.replace(queryParameters: params.isNotEmpty ? params : null);
  }

  // --- Multi-Instance Management ---

  Future<List<InstanceItem>> getInstances() async {
    final res = await http.get(Uri.parse('$baseUrl/api/instances'));
    if (res.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is List) {
        final list = decoded.map((e) => InstanceItem.fromJson(e)).toList();
        if (list.isEmpty) {
          if (currentInstanceId != null) {
            currentInstanceId = null;
            currentInstanceName = null;
            activeInstanceNotifier.value = null;
          }
        } else {
          // If current instance is unset or was deleted, default to active or first
          if (currentInstanceId == null || !list.any((i) => i.id == currentInstanceId)) {
            final active = list.firstWhere((i) => i.isActive, orElse: () => list.first);
            currentInstanceId = active.id;
            currentInstanceName = active.name;
            activeInstanceNotifier.value = active.id;
          } else {
            final cur = list.firstWhere((i) => i.id == currentInstanceId);
            currentInstanceName = cur.name;
          }
        }
        return list;
      }
    }
    throw Exception('Failed to load instances: ${res.statusCode}');
  }

  Future<InstanceItem> createInstance(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/instances'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (res.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final inst = InstanceItem.fromJson(decoded['instance'] as Map<String, dynamic>);
      if (currentInstanceId == null) {
        currentInstanceId = inst.id;
        activeInstanceNotifier.value = inst.id;
      }
      return inst;
    }
    throw Exception(res.body);
  }

  Future<void> switchInstance(String id) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/instances/switch'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id': id}),
    );
    if (res.statusCode == 200) {
      currentInstanceId = id;
      try {
        final list = await getInstances();
        final cur = list.where((i) => i.id == id).firstOrNull;
        currentInstanceName = cur?.name;
      } catch (_) {}
      activeInstanceNotifier.value = id;
      return;
    }
    throw Exception(res.body);
  }

  Future<void> updateInstance(String id, Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/instances/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> deleteInstance(String id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/instances/$id'));
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
    final list = await getInstances();
    if (list.isNotEmpty) {
      // User requirement: "当左侧栏删除实例后, 会跳转到第一个实例"
      final first = list.first;
      currentInstanceId = first.id;
      activeInstanceNotifier.value = first.id;
      try {
        await switchInstance(first.id);
      } catch (_) {}
    } else {
      currentInstanceId = null;
      activeInstanceNotifier.value = null;
    }
  }

  Future<void> startInstance(String id) async {
    final res = await http.post(Uri.parse('$baseUrl/api/instances/$id/start'));
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> stopInstance(String id) async {
    final res = await http.post(Uri.parse('$baseUrl/api/instances/$id/stop'));
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> restartInstance(String id) async {
    final res = await http.post(Uri.parse('$baseUrl/api/instances/$id/restart'));
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  // --- Status & Control (Scoped to active instance) ---

  Future<ServerStatus> getStatus() async {
    final res = await http.get(_buildUri('/api/status'));
    if (res.statusCode == 200) {
      final st = ServerStatus.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
      if (st.version.isNotEmpty) {
        AppVersion.update(st.version);
      }
      return st;
    }
    throw Exception('Failed to load status: ${res.statusCode}');
  }

  Future<String> fetchVersion() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/version'));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map && decoded['version'] is String) {
          AppVersion.update(decoded['version']);
          return decoded['version'];
        }
      }
    } catch (_) {}
    return AppVersion.current;
  }

  Future<void> startServer() async {
    final res = await http.post(_buildUri('/api/server/start'));
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> stopServer() async {
    final res = await http.post(_buildUri('/api/server/stop'));
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> restartServer() async {
    final res = await http.post(_buildUri('/api/server/restart'));
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> updateServer({String steamUser = '', String steamPass = ''}) async {
    final res = await http.post(
      _buildUri('/api/server/update'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'steamUser': steamUser, 'steamPass': steamPass}),
    );
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  // --- Configuration ---

  Future<ServerConfig> getConfig() async {
    final res = await http.get(_buildUri('/api/config'));
    if (res.statusCode == 200) {
      return ServerConfig.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    }
    throw Exception('Failed to load config: ${res.statusCode}');
  }

  Future<ServerConfig> saveConfig(ServerConfig config) async {
    final res = await http.post(
      _buildUri('/api/config'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(config.toJson()),
    );
    if (res.statusCode == 200) {
      return ServerConfig.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    }
    throw Exception(res.body);
  }

  // --- Proxy & Clash Controller (Instance-Scoped) ---

  Future<Map<String, dynamic>> testProxy({
    required String proxyType,
    required String proxyAddress,
    String clashApiUrl = '',
    String clashSecret = '',
  }) async {
    final res = await http.post(
      _buildUri('/api/proxy/test'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'proxyType': proxyType,
        'proxyAddress': proxyAddress,
        'clashApiUrl': clashApiUrl,
        'clashSecret': clashSecret,
      }),
    );
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> testClash({
    required String clashApiUrl,
    required String clashSecret,
  }) async {
    final res = await http.post(
      _buildUri('/api/clash/test'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'clashApiUrl': clashApiUrl,
        'clashSecret': clashSecret,
      }),
    );
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> testClashController({
    required String clashApiUrl,
    required String clashSecret,
  }) => testClash(clashApiUrl: clashApiUrl, clashSecret: clashSecret);

  Future<Map<String, dynamic>> switchClashNode({
    required String clashApiUrl,
    required String clashSecret,
    required String group,
    required String node,
  }) async {
    final res = await http.post(
      _buildUri('/api/clash/switch-node'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'clashApiUrl': clashApiUrl,
        'clashSecret': clashSecret,
        'group': group,
        'node': node,
      }),
    );
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveProxyConfig({
    required bool proxyEnabled,
    bool proxySDR = true,
    bool proxySteamCmd = true,
    bool proxyMods = true,
    bool proxyDiscord = true,
    required String proxyType,
    required String proxyAddress,
    required String clashApiUrl,
    required String clashSecret,
    String clashNode = '',
    String clashGroup = '',
  }) async {
    final res = await http.post(
      _buildUri('/api/config/proxy'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
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
      }),
    );
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> testDiscordWebhook({
    required String webhookUrl,
    String botName = '',
    String avatarUrl = '',
  }) async {
    final res = await http.post(
      _buildUri('/api/discord/test'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'webhookUrl': webhookUrl,
        'botName': botName,
        'avatarUrl': avatarUrl,
      }),
    );
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  // --- Admins (Instance-Scoped) ---

  Future<List<AdminItem>> getAdmins() async {
    final res = await http.get(_buildUri('/api/admins'));
    if (res.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded == null || decoded is! List) {
        return [];
      }
      return decoded.map((e) => AdminItem.fromJson(e)).toList();
    }
    throw Exception('Failed to load admins');
  }

  Future<void> addAdmin({required String name, required String steamId, required int privileges}) async {
    final res = await http.post(
      _buildUri('/api/admins'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'steamId': steamId, 'privileges': privileges}),
    );
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> deleteAdmin(String steamId) async {
    final res = await http.delete(_buildUri('/api/admins/$steamId'));
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  // --- Worlds (Instance-Scoped) ---

  Future<List<WorldItem>> getWorlds() async {
    final res = await http.get(_buildUri('/api/worlds'));
    if (res.statusCode == 200) {
      final List list = jsonDecode(utf8.decode(res.bodyBytes));
      return list.map((e) => WorldItem.fromJson(e)).toList();
    }
    throw Exception('Failed to load worlds');
  }

  Future<void> switchWorld(int index) async {
    final res = await http.post(
      _buildUri('/api/worlds/switch'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'index': index}),
    );
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> renameWorld(int index, String newName) async {
    final res = await http.post(
      _buildUri('/api/worlds/rename'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'index': index, 'name': newName}),
    );
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> createWorld({
    int? index,
    required String name,
    required int seed,
    required int mode,
  }) async {
    final Map<String, dynamic> data = {
      'name': name,
      'seed': seed,
      'mode': mode,
    };
    if (index != null && index >= 0) {
      data['index'] = index;
    }
    final res = await http.post(
      _buildUri('/api/worlds/create'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> deleteWorld(int index) async {
    final res = await http.delete(_buildUri('/api/worlds/$index'));
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  String getWorldExportUrl(int index) {
    final uri = _buildUri('/api/worlds/$index/export');
    return uri.toString();
  }

  Future<void> importWorld({
    required Uint8List fileBytes,
    required String filename,
    String? name,
    int mode = 0,
    int seed = 0,
  }) async {
    final uri = _buildUri('/api/worlds/import');
    final req = http.MultipartRequest('POST', uri);
    req.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: filename));
    if (name != null && name.trim().isNotEmpty) {
      req.fields['name'] = name.trim();
    }
    req.fields['mode'] = mode.toString();
    req.fields['seed'] = seed.toString();

    final streamedRes = await req.send();
    final res = await http.Response.fromStream(streamedRes);
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  // --- Mods (Shared Pool with Instance-Specific Enablement) ---

  Future<List<ModItem>> getMods() async {
    final res = await http.get(_buildUri('/api/mods'));
    if (res.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded == null || decoded is! List) {
        return [];
      }
      return decoded.map((e) => ModItem.fromJson(e)).toList();
    }
    throw Exception('Failed to load mods');
  }

  Future<void> installMod(String target) async {
    final res = await http.post(
      _buildUri('/api/mods/install'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'target': target}),
    );
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> installWorkshopMod(String workshopId) async {
    return installMod(workshopId);
  }

  Future<void> uploadMod(List<int> bytes, String filename) async {
    final uri = _buildUri('/api/mods/upload');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    ));
    final streamedResponse = await request.send();
    final res = await http.Response.fromStream(streamedResponse);
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> toggleMod(String modId, bool enabled) async {
    final res = await http.post(
      _buildUri('/api/mods/toggle'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'modId': modId, 'enabled': enabled}),
    );
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> updateMod(String modId) async {
    final res = await http.post(_buildUri('/api/mods/$modId/update'));
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> deleteMod(String modId) async {
    final res = await http.delete(_buildUri('/api/mods/$modId'));
    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  // --- Mod.io Configuration & Testing ---

  Future<Map<String, dynamic>> getModioConfig() async {
    final res = await http.get(_buildUri('/api/modio/config'));
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception('Failed to get Mod.io config');
  }

  Future<Map<String, dynamic>> saveModioConfig(String apiKey) async {
    final res = await http.post(
      _buildUri('/api/modio/config'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'apiKey': apiKey}),
    );
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception(res.body);
  }

  Future<Map<String, dynamic>> testModioApiKey(String apiKey) async {
    final res = await http.post(
      _buildUri('/api/modio/test'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'apiKey': apiKey}),
    );
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception(res.body);
  }

  // --- Real-time Logs via WebSocket (Instance-Aware) ---

  WebSocketChannel connectLogsChannel() {
    final uri = currentInstanceId != null && currentInstanceId!.isNotEmpty
        ? Uri.parse('$wsUrl?instance=$currentInstanceId')
        : Uri.parse(wsUrl);
    return WebSocketChannel.connect(uri);
  }
}
