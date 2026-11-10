import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/server_config.dart';
import '../services/api_service.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import '../widgets/app_toast.dart';
import '../widgets/common_card.dart';
import '../widgets/current_instance_badge.dart';
import '../widgets/elastic_switch.dart';
import '../widgets/icon_well.dart';
import '../widgets/list_row.dart';
import '../widgets/page_header.dart';
import '../widgets/squircle_button.dart';
import '../widgets/status_badge.dart';

class DiscordView extends StatefulWidget {
  final VoidCallback? onConfigSaved;

  const DiscordView({super.key, this.onConfigSaved});

  @override
  State<DiscordView> createState() => _DiscordViewState();
}

class _DiscordViewState extends State<DiscordView> {
  ServerConfig? _config;
  bool _loading = false;
  bool _saving = false;

  bool _discordEnabled = false;
  final _webhookUrlCtrl = TextEditingController();
  final _botNameCtrl = TextEditingController();
  final _avatarUrlCtrl = TextEditingController();
  Map<String, DiscordMessageTemplate> _messages = DiscordConfig.defaultMessages();

  final Map<String, TextEditingController> _titleCtrls = {};
  final Map<String, TextEditingController> _descCtrls = {};
  final Map<String, TextEditingController> _colorCtrls = {};
  final Map<String, bool> _expanded = {};

  bool _testing = false;
  String? _testMessage;
  bool? _testSuccess;

  static const _eventsMeta = [
    {
      'key': 'server_online',
      'titleKey': 'discordEventOnline',
      'vars': ['{server_name}', '{game_id}', '{network_mode}', '{world_name}', '{world_index}', '{max_players}'],
    },
    {
      'key': 'server_offline',
      'titleKey': 'discordEventOffline',
      'vars': ['{server_name}', '{uptime}'],
    },
    {
      'key': 'server_crashed',
      'titleKey': 'discordEventCrashed',
      'vars': ['{server_name}', '{exit_code}', '{error_log}'],
    },
    {
      'key': 'player_join',
      'titleKey': 'discordEventPlayerJoin',
      'vars': ['{player_name}', '{server_name}'],
    },
    {
      'key': 'player_leave',
      'titleKey': 'discordEventPlayerLeave',
      'vars': ['{player_name}', '{server_name}'],
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _webhookUrlCtrl.dispose();
    _botNameCtrl.dispose();
    _avatarUrlCtrl.dispose();
    for (final c in _titleCtrls.values) {
      c.dispose();
    }
    for (final c in _descCtrls.values) {
      c.dispose();
    }
    for (final c in _colorCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _loading = true);
    try {
      final cfg = await ApiService.instance.getConfig();
      setState(() {
        _config = cfg;
        _discordEnabled = cfg.discord.enabled;
        _webhookUrlCtrl.text = cfg.discord.webhookUrl;
        _botNameCtrl.text = cfg.discord.botName;
        _avatarUrlCtrl.text = cfg.discord.avatarUrl;
        _messages = Map.from(cfg.discord.messages);

        for (final entry in _messages.entries) {
          if (_titleCtrls.containsKey(entry.key)) {
            _titleCtrls[entry.key]!.text = entry.value.title;
          } else {
            _titleCtrls[entry.key] = TextEditingController(text: entry.value.title);
          }
          if (_descCtrls.containsKey(entry.key)) {
            _descCtrls[entry.key]!.text = entry.value.description;
          } else {
            _descCtrls[entry.key] = TextEditingController(text: entry.value.description);
          }
          if (_colorCtrls.containsKey(entry.key)) {
            _colorCtrls[entry.key]!.text = entry.value.color;
          } else {
            _colorCtrls[entry.key] = TextEditingController(text: entry.value.color);
          }
        }
        _testSuccess = null;
        _testMessage = null;
      });
    } catch (e) {
      _showToast('Failed to load config: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveConfig() async {
    if (_config == null) return;
    final l10n = context.l10n;
    setState(() => _saving = true);
    try {
      final updatedMessages = <String, DiscordMessageTemplate>{};
      for (final entry in _messages.entries) {
        final key = entry.key;
        updatedMessages[key] = entry.value.copyWith(
          title: _titleCtrls[key]?.text ?? entry.value.title,
          description: _descCtrls[key]?.text ?? entry.value.description,
          color: _colorCtrls[key]?.text ?? entry.value.color,
        );
      }

      final updatedDiscord = DiscordConfig(
        enabled: _discordEnabled,
        webhookUrl: _webhookUrlCtrl.text.trim(),
        botName: _botNameCtrl.text.trim(),
        avatarUrl: _avatarUrlCtrl.text.trim(),
        messages: updatedMessages,
      );

      final updatedConfig = ServerConfig(
        worldIndex: _config!.worldIndex,
        worldName: _config!.worldName,
        worldSeed: _config!.worldSeed,
        maxPlayers: _config!.maxPlayers,
        port: _config!.port,
        ip: _config!.ip,
        password: _config!.password,
        gameId: _config!.gameId,
        networkMode: _config!.networkMode,
        worldMode: _config!.worldMode,
        autoStart: _config!.autoStart,
        autoUpdate: _config!.autoUpdate,
        proxyEnabled: _config!.proxyEnabled,
        proxySDR: _config!.proxySDR,
        proxySteamCmd: _config!.proxySteamCmd,
        proxyMods: _config!.proxyMods,
        proxyDiscord: _config!.proxyDiscord,
        proxyType: _config!.proxyType,
        proxyAddress: _config!.proxyAddress,
        clashApiUrl: _config!.clashApiUrl,
        clashSecret: _config!.clashSecret,
        clashNode: _config!.clashNode,
        clashGroup: _config!.clashGroup,
        discord: updatedDiscord,
      );

      await ApiService.instance.saveConfig(updatedConfig);
      _showToast(l10n.discordSaved);
      widget.onConfigSaved?.call();
    } catch (e) {
      _showToast('Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testWebhook() async {
    final url = _webhookUrlCtrl.text.trim();
    if (url.isEmpty) {
      _showToast(context.l10n.discordWebhookUrlHint, isError: true);
      return;
    }
    setState(() {
      _testing = true;
      _testMessage = null;
      _testSuccess = null;
    });
    try {
      final res = await ApiService.instance.testDiscordWebhook(
        webhookUrl: url,
        botName: _botNameCtrl.text.trim(),
        avatarUrl: _avatarUrlCtrl.text.trim(),
      );
      setState(() {
        _testSuccess = res['success'] == true;
        _testMessage = res['message'] ?? (res['success'] == true ? 'Success' : res['error'] ?? 'Failed');
      });
      _showToast(_testMessage!, isError: _testSuccess != true);
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testMessage = e.toString();
      });
      _showToast('Test failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Color _parseHex(String hex) {
    try {
      var clean = hex.replaceAll('#', '').trim();
      if (clean.length == 6) {
        return Color(int.parse('0xFF$clean'));
      }
    } catch (_) {}
    return const Color(0xFF2ECC71);
  }

  void _insertVariable(String eventKey, String variable) {
    final ctrl = _descCtrls[eventKey];
    if (ctrl == null) return;
    final text = ctrl.text;
    final selection = ctrl.selection;
    if (selection.start >= 0 && selection.end >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, variable);
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + variable.length),
      );
    } else {
      ctrl.text = '$text $variable';
    }
    setState(() {});
  }

  void _resetEventToDefault(String eventKey) {
    final defaults = DiscordConfig.defaultMessages();
    final def = defaults[eventKey];
    if (def == null) return;
    setState(() {
      _messages[eventKey] = def;
      _titleCtrls[eventKey]?.text = def.title;
      _descCtrls[eventKey]?.text = def.description;
      _colorCtrls[eventKey]?.text = def.color;
    });
    _showToast(context.l10n.discordResetDefault);
  }

  String _getEventName(AppLocalizations l10n, String titleKey) {
    switch (titleKey) {
      case 'discordEventOnline':
        return l10n.discordEventOnline;
      case 'discordEventOffline':
        return l10n.discordEventOffline;
      case 'discordEventCrashed':
        return l10n.discordEventCrashed;
      case 'discordEventPlayerJoin':
        return l10n.discordEventPlayerJoin;
      case 'discordEventPlayerLeave':
        return l10n.discordEventPlayerLeave;
      default:
        return titleKey;
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    showAppToast(
      context,
      msg,
      type: isError ? ToastType.error : ToastType.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = context.l10n;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          PageHeader(
            title: l10n.discordWebhookSection,
            subtitle: l10n.discordWebhookSectionDesc,
            actionsBuilder: (context, isCompact) => [
              CurrentInstanceBadge(onInstanceChanged: _loadConfig, isCompact: isCompact),
              SquircleButton(
                variant: ButtonVariant.primary,
                icon: const Icon(Icons.save_rounded, size: 16),
                isLoading: _saving,
                onPressed: _saveConfig,
                tooltip: l10n.save,
                child: isCompact ? null : Text(l10n.save),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Master & Connection Card
          CommonCard(
            title: l10n.enableDiscordWebhook,
            leading: const IconWell(
              icon: Icon(Icons.notifications_active_rounded, color: Color(0xFF5865F2), size: 18),
              size: 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListRow(
                  title: l10n.enableDiscordWebhook,
                  subtitle: l10n.enableDiscordWebhookDesc,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  trailing: ElasticSwitch(
                    value: _discordEnabled,
                    onChanged: (v) => setState(() => _discordEnabled = v),
                  ),
                  onTap: () => setState(() => _discordEnabled = !_discordEnabled),
                ),

                if (_discordEnabled) ...[
                  const SizedBox(height: 14),
                  const ListRowSeparator(indent: 0, endIndent: 0),
                  const SizedBox(height: 14),

                  // Webhook URL
                  Text(
                    l10n.discordWebhookUrl,
                    style: AppTextStyle.subheadline.of(context, emphasized: true),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _webhookUrlCtrl,
                    decoration: InputDecoration(
                      hintText: l10n.discordWebhookUrlHint,
                      prefixIcon: const Icon(Icons.link_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Bot Name & Avatar URL
                  if (isMobile) ...[
                    Text(
                      l10n.discordBotName,
                      style: AppTextStyle.subheadline.of(context, emphasized: true),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _botNameCtrl,
                      decoration: InputDecoration(
                        hintText: l10n.discordBotNameHint,
                        prefixIcon: const Icon(Icons.smart_toy_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.discordAvatarUrl,
                      style: AppTextStyle.subheadline.of(context, emphasized: true),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _avatarUrlCtrl,
                      decoration: InputDecoration(
                        hintText: l10n.discordAvatarUrlHint,
                        prefixIcon: const Icon(Icons.image_rounded, size: 18),
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.discordBotName,
                                style: AppTextStyle.subheadline.of(context, emphasized: true),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _botNameCtrl,
                                decoration: InputDecoration(
                                  hintText: l10n.discordBotNameHint,
                                  prefixIcon: const Icon(Icons.smart_toy_rounded, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.discordAvatarUrl,
                                style: AppTextStyle.subheadline.of(context, emphasized: true),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _avatarUrlCtrl,
                                decoration: InputDecoration(
                                  hintText: l10n.discordAvatarUrlHint,
                                  prefixIcon: const Icon(Icons.image_rounded, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Test button & status badge
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SquircleButton(
                        variant: ButtonVariant.secondary,
                        icon: const Icon(Icons.send_rounded, size: 16),
                        isLoading: _testing,
                        onPressed: _testWebhook,
                        child: Text(l10n.discordTestBtn),
                      ),
                      if (_testSuccess != null) ...[
                        StatusBadge(
                          label: _testMessage ?? '',
                          type: _testSuccess! ? BadgeType.success : BadgeType.error,
                          icon: Icon(
                            _testSuccess! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            size: 13,
                            color: _testSuccess!
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

          if (_discordEnabled) ...[
            const SizedBox(height: 16),

            // Event Message Templates Card
            CommonCard(
              title: l10n.discordMsgEvents,
              leading: IconWell(
                icon: Icon(
                  Icons.message_rounded,
                  color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                  size: 18,
                ),
                size: 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.discordMsgEventsDesc,
                    style: AppTextStyle.caption1.of(context).copyWith(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 14),

                  ..._eventsMeta.map((eventMeta) {
                    final key = eventMeta['key'] as String;
                    final tmpl = _messages[key] ?? DiscordConfig.defaultMessages()[key]!;
                    final titleKey = eventMeta['titleKey'] as String;
                    final eventName = _getEventName(l10n, titleKey);
                    final vars = eventMeta['vars'] as List<String>;
                    final isExpanded = _expanded[key] ?? false;
                    final currentColor = _parseHex(_colorCtrls[key]?.text ?? tmpl.color);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surfaceBlockDark : AppColors.surfaceBlockLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? AppColors.dividerHairlineDark : AppColors.dividerHairlineLight,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                _expanded[key] = !isExpanded;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: currentColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      eventName,
                                      style: AppTextStyle.subheadline.of(context, emphasized: true),
                                    ),
                                  ),
                                  ElasticSwitch(
                                    value: tmpl.enabled,
                                    onChanged: (val) {
                                      setState(() {
                                        _messages[key] = tmpl.copyWith(enabled: val);
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                    size: 20,
                                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          if (isExpanded) ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Color row
                                  Row(
                                    children: [
                                      Text(
                                        l10n.discordColor,
                                        style: AppTextStyle.caption1.of(context, emphasized: true),
                                      ),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        width: 100,
                                        child: TextField(
                                          controller: _colorCtrls[key],
                                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                                          onChanged: (hex) {
                                            setState(() {
                                              _messages[key] = tmpl.copyWith(color: hex);
                                            });
                                          },
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: currentColor,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isDark ? Colors.white24 : Colors.black12,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      SquircleButton(
                                        variant: ButtonVariant.ghost,
                                        height: 30,
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        icon: const Icon(Icons.restart_alt_rounded, size: 14),
                                        onPressed: () => _resetEventToDefault(key),
                                        child: Text(l10n.discordResetDefault, style: const TextStyle(fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Preset circles
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      '#2ECC71', '#3498DB', '#9B59B6', '#E67E22',
                                      '#E74C3C', '#F1C40F', '#1ABC9C', '#95A5A6',
                                    ].map((hex) {
                                      final c = _parseHex(hex);
                                      final isSelected = (_colorCtrls[key]?.text.trim().toLowerCase() == hex.toLowerCase());
                                      return InkWell(
                                        onTap: () {
                                          _colorCtrls[key]?.text = hex;
                                          setState(() {
                                            _messages[key] = tmpl.copyWith(color: hex);
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            color: c,
                                            shape: BoxShape.circle,
                                            border: isSelected
                                                ? Border.all(color: Colors.white, width: 2)
                                                : null,
                                            boxShadow: isSelected
                                                ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 4, spreadRadius: 1)]
                                                : null,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 14),

                                  // Title field
                                  Text(
                                    l10n.discordMsgTitle,
                                    style: AppTextStyle.caption1.of(context, emphasized: true),
                                  ),
                                  const SizedBox(height: 4),
                                  TextField(
                                    controller: _titleCtrls[key],
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Description field
                                  Text(
                                    l10n.discordMsgDesc,
                                    style: AppTextStyle.caption1.of(context, emphasized: true),
                                  ),
                                  const SizedBox(height: 4),
                                  TextField(
                                    controller: _descCtrls[key],
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.all(10),
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // Clickable variables
                                  Text(
                                    l10n.discordAvailVars,
                                    style: AppTextStyle.caption2.of(context).copyWith(
                                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: vars.map((v) {
                                      return InkWell(
                                        onTap: () => _insertVariable(key, v),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isDark ? Colors.white12 : Colors.black12,
                                            ),
                                          ),
                                          child: Text(
                                            v,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
