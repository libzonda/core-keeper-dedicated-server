import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/server_config.dart';
import '../services/api_service.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import '../widgets/app_dialog.dart';
import '../widgets/common_card.dart';
import '../widgets/current_instance_badge.dart';
import '../widgets/delay_chip.dart';
import '../widgets/elastic_switch.dart';
import '../widgets/icon_well.dart';
import '../widgets/list_row.dart';
import '../widgets/page_header.dart';
import '../widgets/restart_prompt.dart';
import '../widgets/segmented_control.dart';
import '../widgets/squircle_button.dart';
import '../widgets/status_badge.dart';

class ConfigView extends StatefulWidget {
  final VoidCallback onConfigSaved;

  const ConfigView({super.key, required this.onConfigSaved});

  @override
  State<ConfigView> createState() => _ConfigViewState();
}

class _ConfigViewState extends State<ConfigView> {
  ServerConfig? _config;
  bool _loading = false;
  bool _saving = false;

  // Controllers
  final _maxPlayersCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _ipCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _gameIdCtrl = TextEditingController();

  String _networkMode = 'sdr';
  bool _autoStart = true;
  bool _autoUpdate = true;

  // Proxy settings
  bool _proxyEnabled = false;
  bool _proxySDR = true;
  bool _proxySteamCmd = true;
  bool _proxyMods = true;
  String _proxyType = 'http';
  final _proxyAddressCtrl = TextEditingController();
  final _clashApiUrlCtrl = TextEditingController();
  final _clashSecretCtrl = TextEditingController();

  bool _testingProxy = false;
  String? _proxyTestMessage;
  bool? _proxyTestSuccess;

  // Clash dynamic node state
  String? _clashCurrentNode;
  String? _clashCurrentNodeType;
  int _clashCurrentNodeDelay = 0;
  String? _clashCurrentGroup;
  List<String> _clashAvailableNodes = [];
  bool _switchingNode = false;
  bool _savingProxy = false;

  @override
  void initState() {
    super.initState();
    _clashApiUrlCtrl.addListener(_onClashConfigChanged);
    _clashSecretCtrl.addListener(_onClashConfigChanged);
    _loadConfig();
  }

  void _onClashConfigChanged() {
    if (_clashCurrentNode != null || _proxyTestSuccess != null) {
      setState(() {
        _clashCurrentNode = null;
        _clashAvailableNodes = [];
        _clashCurrentNodeType = null;
        _clashCurrentGroup = null;
        _clashCurrentNodeDelay = 0;
        _proxyTestSuccess = null;
        _proxyTestMessage = null;
      });
    }
  }

  @override
  void dispose() {
    _clashApiUrlCtrl.removeListener(_onClashConfigChanged);
    _clashSecretCtrl.removeListener(_onClashConfigChanged);
    _maxPlayersCtrl.dispose();
    _portCtrl.dispose();
    _ipCtrl.dispose();
    _passwordCtrl.dispose();
    _gameIdCtrl.dispose();
    _proxyAddressCtrl.dispose();
    _clashApiUrlCtrl.dispose();
    _clashSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _loading = true);
    try {
      final cfg = await ApiService.instance.getConfig();
      setState(() {
        _config = cfg;
        _networkMode = cfg.networkMode;
        _maxPlayersCtrl.text = cfg.maxPlayers.toString();
        _portCtrl.text = cfg.port.toString();
        _ipCtrl.text = cfg.ip;
        _passwordCtrl.text = cfg.password;
        _gameIdCtrl.text = cfg.gameId;
        _autoStart = cfg.autoStart;
        _autoUpdate = cfg.autoUpdate;

        _proxyEnabled = cfg.proxyEnabled;
        _proxySDR = cfg.proxySDR;
        _proxySteamCmd = cfg.proxySteamCmd;
        _proxyMods = cfg.proxyMods;
        _proxyType = cfg.proxyType.isNotEmpty ? cfg.proxyType : 'http';
        _proxyAddressCtrl.text = cfg.proxyAddress;
        _clashApiUrlCtrl.text = cfg.clashApiUrl.isNotEmpty ? cfg.clashApiUrl : 'http://127.0.0.1:9090';
        _clashSecretCtrl.text = cfg.clashSecret;
        _clashCurrentNode = null;
        _clashCurrentGroup = null;
        _clashAvailableNodes = [];
        _proxyTestSuccess = null;
        _proxyTestMessage = null;
      });

      // Auto-detect Clash node silently if enabled
      if (cfg.proxyEnabled && cfg.proxyType == 'clash') {
        _detectClashSilently();
      }
    } catch (e) {
      _showToast('Error loading config: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _detectClashSilently() async {
    try {
      final res = await ApiService.instance.testClash(
        clashApiUrl: _clashApiUrlCtrl.text.trim(),
        clashSecret: _clashSecretCtrl.text.trim(),
      );
      if (res['success'] == true && mounted) {
        setState(() {
          _clashCurrentNode = res['currentNode'] as String?;
          _clashCurrentNodeType = res['currentNodeType'] as String?;
          _clashCurrentNodeDelay = (res['currentNodeDelay'] as num?)?.toInt() ?? 0;
          _clashCurrentGroup = res['currentGroup'] as String?;
          if (res['availableNodes'] != null) {
            _clashAvailableNodes = List<String>.from(res['availableNodes']);
          }
          _proxyTestSuccess = true;
          _proxyTestMessage = 'Clash: $_clashCurrentNode';
        });
      }
    } catch (_) {}
  }

  Future<void> _testProxy() async {
    setState(() {
      _testingProxy = true;
      _proxyTestMessage = null;
      _proxyTestSuccess = null;
    });

    try {
      final res = await ApiService.instance.testProxy(
        proxyType: _proxyType,
        proxyAddress: _proxyAddressCtrl.text.trim(),
        clashApiUrl: _clashApiUrlCtrl.text.trim(),
        clashSecret: _clashSecretCtrl.text.trim(),
      );

      final ok = res['success'] == true;
      final msg = res['message'] as String? ?? (ok ? 'Connected' : 'Failed');
      final latency = (res['latencyMs'] as num?)?.toInt() ?? 0;
      final err = res['error'] as String?;

      setState(() {
        _proxyTestSuccess = ok;
        _proxyTestMessage = ok && latency > 0
            ? '$msg (${latency}ms)'
            : (err != null && err.isNotEmpty && !msg.contains(err) ? '$msg: $err' : msg);

        if (ok && res['clash'] != null) {
          final clash = res['clash'] as Map<String, dynamic>;
          _clashCurrentNode = clash['currentNode'] as String?;
          _clashCurrentNodeType = clash['currentNodeType'] as String?;
          _clashCurrentNodeDelay = (clash['currentNodeDelay'] as num?)?.toInt() ?? 0;
          _clashCurrentGroup = clash['currentGroup'] as String?;
          if (clash['availableNodes'] != null) {
            _clashAvailableNodes = List<String>.from(clash['availableNodes']);
          }
        }
      });
      _showToast(_proxyTestMessage!, isError: !ok);
    } catch (e) {
      setState(() {
        _proxyTestSuccess = false;
        _proxyTestMessage = 'Test error: $e';
      });
      _showToast('Test failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _testingProxy = false);
    }
  }

  Future<void> _switchClashNode(String newNode) async {
    if (_clashCurrentGroup == null || _clashCurrentGroup!.isEmpty) return;

    setState(() => _switchingNode = true);
    try {
      final res = await ApiService.instance.switchClashNode(
        clashApiUrl: _clashApiUrlCtrl.text.trim(),
        clashSecret: _clashSecretCtrl.text.trim(),
        group: _clashCurrentGroup!,
        node: newNode,
      );

      if (res['success'] == true) {
        setState(() {
          _clashCurrentNode = newNode;
          _proxyTestMessage = 'Node: $newNode';
        });
        _showToast('Switched to: $newNode');
        _saveProxyConfigOnly();
      } else {
        _showToast(res['message'] ?? 'Failed to switch node', isError: true);
      }
    } catch (e) {
      _showToast('Switch error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _switchingNode = false);
    }
  }

  Future<void> _saveProxyConfigOnly() async {
    final l10n = context.l10n;
    setState(() => _savingProxy = true);
    try {
      await ApiService.instance.saveProxyConfig(
        proxyEnabled: _proxyEnabled,
        proxySDR: _proxySDR,
        proxySteamCmd: _proxySteamCmd,
        proxyMods: _proxyMods,
        proxyType: _proxyType,
        proxyAddress: _proxyAddressCtrl.text.trim(),
        clashApiUrl: _clashApiUrlCtrl.text.trim(),
        clashSecret: _clashSecretCtrl.text.trim(),
        clashNode: _clashCurrentNode ?? '',
        clashGroup: _clashCurrentGroup ?? '',
      );
      _showToast(l10n.proxySaved);
      if (mounted) {
        await checkAndPromptRestart(
          context,
          title: l10n.restartPromptTitle,
          reason: l10n.restartPromptReason,
        );
      }
    } catch (e) {
      _showToast('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingProxy = false);
    }
  }

  Future<void> _saveConfig() async {
    if (_config == null) return;
    final l10n = context.l10n;

    final confirm = await showAppDialog(
      context: context,
      title: l10n.confirmSaveConfigTitle,
      content: l10n.confirmSaveConfigDesc,
      confirmText: l10n.confirm,
    );

    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      final updated = ServerConfig(
        worldIndex: _config?.worldIndex ?? 0,
        worldName: _config?.worldName ?? "libzonda's Dedicated Server",
        worldSeed: _config?.worldSeed ?? 0,
        maxPlayers: int.tryParse(_maxPlayersCtrl.text.trim()) ?? 10,
        port: int.tryParse(_portCtrl.text.trim()) ?? 27015,
        ip: _ipCtrl.text.trim().isEmpty ? '0.0.0.0' : _ipCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
        gameId: _gameIdCtrl.text.trim(),
        networkMode: _networkMode,
        worldMode: _config?.worldMode ?? 0,
        autoStart: _autoStart,
        autoUpdate: _autoUpdate,
        proxyEnabled: _proxyEnabled,
        proxySDR: _proxySDR,
        proxySteamCmd: _proxySteamCmd,
        proxyMods: _proxyMods,
        proxyType: _proxyType,
        proxyAddress: _proxyAddressCtrl.text.trim(),
        clashApiUrl: _clashApiUrlCtrl.text.trim(),
        clashSecret: _clashSecretCtrl.text.trim(),
        clashNode: _clashCurrentNode ?? '',
        clashGroup: _clashCurrentGroup ?? '',
      );

      await ApiService.instance.saveConfig(updated);
      _showToast(l10n.configSaved);
      widget.onConfigSaved();

      if (mounted) {
        await checkAndPromptRestart(
          context,
          title: l10n.restartPromptTitle,
          reason: l10n.restartPromptReason,
        );
      }
    } catch (e) {
      _showToast('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? (isDark ? AppColors.stateErrorBgDark : AppColors.stateErrorBgLight)
            : SurfaceLevel.block.colorOf(context),
        behavior: SnackBarBehavior.floating,
        shape: AppShape.sm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = context.l10n;
    final primaryColor = isDark ? AppColors.primaryDark : AppColors.primaryLight;

    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          PageHeader(
            title: l10n.configTitle,
            subtitle: l10n.configSubtitle,
            actions: [
              CurrentInstanceBadge(onInstanceChanged: _loadConfig),
              SquircleButton(
                variant: ButtonVariant.primary,
                icon: const Icon(Icons.save_rounded, size: 16),
                isLoading: _saving,
                onPressed: _saveConfig,
                child: Text(l10n.saveAllConfig),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Network Mode Card with SegmentedControl Capsule
          CommonCard(
            title: l10n.networkModeTitle,
            leading: IconWell(
              icon: Icon(Icons.hub_rounded, color: primaryColor, size: 18),
              size: 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedControl<String>.tabs(
                  tabs: [
                    SegmentTab(
                      value: 'sdr',
                      title: l10n.sdrModeTitle,
                      subtitle: l10n.sdrModeSubtitle,
                      icon: Icons.cloud_sync_rounded,
                    ),
                    SegmentTab(
                      value: 'direct',
                      title: l10n.directModeTitle,
                      subtitle: l10n.directModeSubtitle,
                      icon: Icons.lan_rounded,
                    ),
                  ],
                  value: _networkMode,
                  onChanged: (val) => setState(() => _networkMode = val),
                ),
                const SizedBox(height: 16),

                if (_networkMode == 'sdr') ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.fixedGameId,
                        style: AppTextStyle.subheadline.of(context, emphasized: true),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _gameIdCtrl,
                        decoration: InputDecoration(
                          hintText: l10n.gameIdHint,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.serverIp,
                              style: AppTextStyle.subheadline.of(context, emphasized: true),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _ipCtrl,
                              decoration: const InputDecoration(hintText: '0.0.0.0'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.serverPort,
                              style: AppTextStyle.subheadline.of(context, emphasized: true),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _portCtrl,
                              decoration: const InputDecoration(hintText: '27015'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.serverPassword,
                            style: AppTextStyle.subheadline.of(context, emphasized: true),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _passwordCtrl,
                            obscureText: true,
                            decoration: InputDecoration(
                              hintText: l10n.serverPasswordHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.maxPlayers,
                            style: AppTextStyle.subheadline.of(context, emphasized: true),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _maxPlayersCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(hintText: '10'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Proxy & Acceleration Card
          CommonCard(
            title: l10n.proxySettingsTitle,
            leading: IconWell(
              icon: Icon(
                Icons.speed_rounded,
                color: isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight,
                size: 18,
              ),
              size: 32,
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListRow(
                  title: l10n.proxyEnableTitle,
                  subtitle: l10n.proxyEnableSubtitle,
                  padding: EdgeInsets.zero,
                  trailing: ElasticSwitch(
                    value: _proxyEnabled,
                    onChanged: (v) => setState(() => _proxyEnabled = v),
                  ),
                  onTap: () => setState(() => _proxyEnabled = !_proxyEnabled),
                ),

                if (_proxyEnabled) ...[
                  const SizedBox(height: 16),
                  const ListRowSeparator(indent: 0, endIndent: 0),
                  const SizedBox(height: 16),

                  Text(
                    l10n.proxyTypeLabel,
                    style: AppTextStyle.subheadline.of(context, emphasized: true),
                  ),
                  const SizedBox(height: 8),

                  SegmentedControl<String>(
                    segments: [
                      ('http', l10n.proxyTypeHttp),
                      ('socks5', l10n.proxyTypeSocks),
                      ('clash', l10n.proxyTypeClash),
                    ],
                    value: _proxyType,
                    onChanged: (val) => setState(() => _proxyType = val),
                  ),
                  const SizedBox(height: 16),

                  if (_proxyType == 'clash') ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.clashApiUrl,
                                style: AppTextStyle.subheadline.of(context, emphasized: true),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _clashApiUrlCtrl,
                                decoration: const InputDecoration(
                                  hintText: 'http://192.168.1.100:9090',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.clashSecret,
                                style: AppTextStyle.subheadline.of(context, emphasized: true),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _clashSecretCtrl,
                                decoration: InputDecoration(
                                  hintText: l10n.clashSecretHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.clashTip,
                      style: AppTextStyle.footnote.of(
                        context,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),

                    // Active Node card or unverified guide box
                    if (_proxyTestSuccess == true && _clashCurrentNode != null && _clashCurrentNode!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: ShapeDecoration(
                          color: SurfaceLevel.block.colorOf(context),
                          shape: AppShape.sm.copyWith(
                            side: BorderSide(
                              color: (isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight).withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.hub_rounded,
                                  color: isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.clashActiveNode,
                                  style: AppTextStyle.subheadline.of(context, emphasized: true),
                                ),
                                const Spacer(),
                                if (_clashCurrentGroup != null && _clashCurrentGroup!.isNotEmpty)
                                  StatusBadge(
                                    label: l10n.clashStrategyGroup(_clashCurrentGroup!),
                                    type: BadgeType.neutral,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _clashCurrentNode!,
                                    style: AppTextStyle.headline.of(context, emphasized: true),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_clashCurrentNodeType != null && _clashCurrentNodeType!.isNotEmpty)
                                  StatusBadge(
                                    label: _clashCurrentNodeType!,
                                    type: BadgeType.neutral,
                                  ),
                                if (_clashCurrentNodeDelay > 0) ...[
                                  const SizedBox(width: 6),
                                  DelayChip(delay: _clashCurrentNodeDelay),
                                ],
                              ],
                            ),
                            if (_clashAvailableNodes.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const ListRowSeparator(indent: 0, endIndent: 0),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text(
                                    l10n.clashSwitchNode,
                                    style: AppTextStyle.subheadline.of(
                                      context,
                                      emphasized: true,
                                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _clashAvailableNodes.contains(_clashCurrentNode) ? _clashCurrentNode : _clashAvailableNodes.first,
                                      dropdownColor: SurfaceLevel.card.colorOf(context),
                                      isDense: true,
                                      items: _clashAvailableNodes.map((n) {
                                        return DropdownMenuItem<String>(
                                          value: n,
                                          child: Text(n, overflow: TextOverflow.ellipsis),
                                        );
                                      }).toList(),
                                      onChanged: _switchingNode
                                          ? null
                                          : (val) {
                                              if (val != null && val != _clashCurrentNode) {
                                                _switchClashNode(val);
                                              }
                                            },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: ShapeDecoration(
                          color: SurfaceLevel.block.colorOf(context),
                          shape: AppShape.sm.copyWith(
                            side: BorderSide(
                              color: isDark ? AppColors.dividerHairlineDark : AppColors.dividerHairlineLight,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _proxyTestSuccess == false
                                    ? l10n.clashTestFailTip
                                    : l10n.clashUnverifiedTip,
                                style: AppTextStyle.footnote.of(
                                  context,
                                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ] else ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _proxyType == 'socks5' ? l10n.socks5Address : l10n.httpAddress,
                          style: AppTextStyle.subheadline.of(context, emphasized: true),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _proxyAddressCtrl,
                          decoration: InputDecoration(
                            hintText: _proxyType == 'socks5'
                                ? 'socks5://192.168.1.100:7890'
                                : 'http://192.168.1.100:7890',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.proxyAddressTip,
                          style: AppTextStyle.caption2.of(
                            context,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),
                  const ListRowSeparator(indent: 0, endIndent: 0),
                  const SizedBox(height: 14),

                  Text(
                    l10n.proxyScopeTitle,
                    style: AppTextStyle.subheadline.of(context, emphasized: true),
                  ),
                  const SizedBox(height: 8),

                  ListRow(
                    title: l10n.proxySDR,
                    subtitle: l10n.proxySDRDesc,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    trailing: ElasticSwitch(
                      value: _proxySDR,
                      onChanged: (v) => setState(() => _proxySDR = v),
                    ),
                    onTap: () => setState(() => _proxySDR = !_proxySDR),
                  ),
                  const ListRowSeparator(indent: 0, endIndent: 0),
                  ListRow(
                    title: l10n.proxySteamCmd,
                    subtitle: l10n.proxySteamCmdDesc,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    trailing: ElasticSwitch(
                      value: _proxySteamCmd,
                      onChanged: (v) => setState(() => _proxySteamCmd = v),
                    ),
                    onTap: () => setState(() => _proxySteamCmd = !_proxySteamCmd),
                  ),
                  const ListRowSeparator(indent: 0, endIndent: 0),
                  ListRow(
                    title: l10n.proxyMods,
                    subtitle: l10n.proxyModsDesc,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    trailing: ElasticSwitch(
                      value: _proxyMods,
                      onChanged: (v) => setState(() => _proxyMods = v),
                    ),
                    onTap: () => setState(() => _proxyMods = !_proxyMods),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      SquircleButton(
                        variant: ButtonVariant.secondary,
                        icon: const Icon(Icons.network_check_rounded, size: 16),
                        isLoading: _testingProxy,
                        onPressed: _testProxy,
                        child: Text(_proxyType == 'clash' ? l10n.testClashNode : l10n.testProxy),
                      ),
                      const SizedBox(width: 10),
                      SquircleButton(
                        variant: ButtonVariant.primary,
                        icon: const Icon(Icons.save_rounded, size: 16),
                        isLoading: _savingProxy,
                        onPressed: _saveProxyConfigOnly,
                        child: Text(l10n.saveProxy),
                      ),
                      const SizedBox(width: 14),
                      if (_proxyTestSuccess != null) ...[
                        StatusBadge(
                          label: _proxyTestMessage ?? '',
                          type: _proxyTestSuccess! ? BadgeType.success : BadgeType.error,
                          icon: Icon(
                            _proxyTestSuccess! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            size: 13,
                            color: _proxyTestSuccess!
                                ? (isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight)
                                : (isDark ? AppColors.stateErrorDark : AppColors.stateErrorLight),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Container Automation Card with ElasticSwitches
          CommonCard(
            title: l10n.automationSettingsTitle,
            leading: IconWell(
              icon: Icon(
                Icons.settings_suggest_rounded,
                color: isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight,
                size: 18,
              ),
              size: 32,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                ListRow(
                  title: l10n.autoStart,
                  subtitle: l10n.autoStartSubtitle,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  trailing: ElasticSwitch(
                    value: _autoStart,
                    onChanged: (v) => setState(() => _autoStart = v),
                  ),
                  onTap: () => setState(() => _autoStart = !_autoStart),
                ),
                const ListRowSeparator(indent: 0, endIndent: 0),
                ListRow(
                  title: l10n.autoUpdate,
                  subtitle: l10n.autoUpdateSubtitle,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  trailing: ElasticSwitch(
                    value: _autoUpdate,
                    onChanged: (v) => setState(() => _autoUpdate = v),
                  ),
                  onTap: () => setState(() => _autoUpdate = !_autoUpdate),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
