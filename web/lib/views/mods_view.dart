import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/mod_item.dart';
import '../services/api_service.dart';
import '../services/restart_state_controller.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import '../utils/file_picker_helper.dart';
import '../widgets/app_dialog.dart';
import '../widgets/common_card.dart';
import '../widgets/current_instance_badge.dart';
import '../widgets/elastic_switch.dart';
import '../widgets/icon_well.dart';
import '../widgets/list_row.dart';
import '../widgets/page_header.dart';
import '../widgets/squircle_button.dart';
import '../widgets/status_badge.dart';

class ModsView extends StatefulWidget {
  const ModsView({super.key});

  @override
  State<ModsView> createState() => _ModsViewState();
}

class _ModsViewState extends State<ModsView> {
  List<ModItem> _mods = [];
  bool _loading = true;
  bool _installing = false;
  bool _uploading = false;
  bool _modioConfigured = false;
  String _modioApiKey = '';
  String? _updatingModId;
  final _inputCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMods();
    _loadModioConfig();
  }

  Future<void> _loadModioConfig() async {
    try {
      final res = await ApiService.instance.getModioConfig();
      if (mounted) {
        setState(() {
          _modioConfigured = res['configured'] == true;
          _modioApiKey = (res['apiKey'] ?? '').toString();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMods() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.instance.getMods();
      if (mounted) setState(() => _mods = list);
    } catch (e) {
      _showToast('Failed to load mods: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _installMod() async {
    final rawInput = _inputCtrl.text.trim();
    if (rawInput.isEmpty) return;

    setState(() => _installing = true);
    final l10n = context.l10n;
    try {
      await ApiService.instance.installMod(rawInput);
      _inputCtrl.clear();
      await _loadMods();
      RestartStateController.instance.markRestartRequired();
      if (mounted) {
        _showToast('${l10n.modInstalledSuccess} ${l10n.autoEnabledForCurrentInstance}');
      }
    } catch (e) {
      if (mounted) {
        _showToast('Install Failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  void _onUploadZip() {
    pickZipFile((bytes, filename) async {
      setState(() => _uploading = true);
      final l10n = context.l10n;
      try {
        await ApiService.instance.uploadMod(bytes, filename);
        await _loadMods();
        RestartStateController.instance.markRestartRequired();
        if (mounted) {
          _showToast('$filename: ${l10n.modInstalledSuccess} ${l10n.autoEnabledForCurrentInstance}');
        }
      } catch (e) {
        if (mounted) {
          _showToast('Upload Failed: $e', isError: true);
        }
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
    });
  }

  Future<void> _updateMod(ModItem mod) async {
    final l10n = context.l10n;
    setState(() => _updatingModId = mod.id);
    try {
      await ApiService.instance.updateMod(mod.id);
      await _loadMods();
      RestartStateController.instance.markRestartRequired();
      if (mounted) {
        _showToast('${mod.name}: ${l10n.modUpdateSuccess}');
      }
    } catch (e) {
      if (mounted) {
        _showToast('Update Failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _updatingModId = null);
    }
  }

  Widget _buildSourceBadge(String source, bool isDark, AppLocalizations l10n) {
    String label;
    IconData icon;
    BadgeType type = BadgeType.neutral;

    switch (source.toLowerCase()) {
      case 'workshop':
        label = l10n.sourceWorkshop;
        icon = Icons.hub_rounded;
        type = BadgeType.primary;
        break;
      case 'modio':
        label = l10n.sourceModio;
        icon = Icons.extension_rounded;
        type = BadgeType.warning;
        break;
      case 'url':
        label = l10n.sourceUrl;
        icon = Icons.link_rounded;
        type = BadgeType.neutral;
        break;
      case 'upload':
      default:
        label = l10n.sourceUpload;
        icon = Icons.folder_zip_rounded;
        type = BadgeType.neutral;
        break;
    }

    return StatusBadge(
      label: label,
      type: type,
      icon: Icon(icon, size: 12),
    );
  }

  Future<void> _toggleMod(ModItem mod, bool enabled) async {
    try {
      await ApiService.instance.toggleMod(mod.id, enabled);
      _showToast('${mod.name}: ${enabled ? "Enabled" : "Disabled"}');
      await _loadMods();
      RestartStateController.instance.markRestartRequired();
    } catch (e) {
      _showToast('Toggle Failed: $e', isError: true);
    }
  }

  Future<void> _deleteMod(ModItem mod) async {
    final l10n = context.l10n;
    final ok = await showAppDialog(
      context: context,
      title: '${l10n.confirmDeleteMod} (${mod.name})',
      content: l10n.confirmDeleteModDesc,
      confirmText: l10n.delete,
      isDestructive: true,
    );

    if (ok == true) {
      try {
        await ApiService.instance.deleteMod(mod.id);
        _showToast('${l10n.delete}: ${mod.name}');
        await _loadMods();
        RestartStateController.instance.markRestartRequired();
      } catch (e) {
        _showToast('Error: $e', isError: true);
      }
    }
  }

  Future<void> _openModioConfigDialog() async {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyCtrl = TextEditingController(text: _modioApiKey);
    bool testing = false;
    bool saving = false;
    String? testMessage;
    bool? testSuccess;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            backgroundColor: SurfaceLevel.card.colorOf(context),
            shape: AppShape.xl,
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconWell(
                          icon: Icon(
                            Icons.vpn_key_rounded,
                            color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                            size: 20,
                          ),
                          size: 36,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.modioConfig,
                                style: AppTextStyle.headline.of(context, emphasized: true),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.modioGlobalNotice,
                                style: AppTextStyle.caption1.of(
                                  context,
                                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.modioConfigDesc,
                      style: AppTextStyle.footnote.of(
                        context,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SurfaceLevel.block.colorOf(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? AppColors.dividerHairlineDark : AppColors.dividerHairlineLight,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 16,
                            color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              'https://mod.io/me/access',
                              style: AppTextStyle.caption1.of(context, emphasized: true).copyWith(
                                color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          Text(
                            l10n.modioApiKeyHelp,
                            style: AppTextStyle.caption1.of(
                              context,
                              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: (isDark ? AppColors.primaryDark : AppColors.primaryLight).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.modioOptionalNotice,
                              style: AppTextStyle.caption1.of(
                                context,
                                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.modioApiKey,
                      style: AppTextStyle.subheadline.of(context, emphasized: true),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: keyCtrl,
                      decoration: InputDecoration(
                        hintText: l10n.modioApiKeyHint,
                        prefixIcon: const Icon(Icons.key_rounded, size: 18),
                        suffixIcon: keyCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  keyCtrl.clear();
                                  setDialogState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    if (testMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: testSuccess == true
                              ? (isDark ? AppColors.stateSuccessBgDark : AppColors.stateSuccessBgLight)
                              : (isDark ? AppColors.stateErrorBgDark : AppColors.stateErrorBgLight),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              testSuccess == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                              size: 18,
                              color: testSuccess == true
                                  ? (isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight)
                                  : (isDark ? AppColors.stateErrorDark : AppColors.stateErrorLight),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                testMessage!,
                                style: AppTextStyle.footnote.of(
                                  context,
                                  color: testSuccess == true
                                      ? (isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight)
                                      : (isDark ? AppColors.stateErrorDark : AppColors.stateErrorLight),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SquircleButton(
                          variant: ButtonVariant.secondary,
                          icon: const Icon(Icons.network_check_rounded, size: 16),
                          isLoading: testing,
                          onPressed: () async {
                            final k = keyCtrl.text.trim();
                            if (k.isEmpty) {
                              setDialogState(() {
                                testSuccess = false;
                                testMessage = l10n.modioKeyEmptyWarning;
                              });
                              return;
                            }
                            setDialogState(() {
                              testing = true;
                              testMessage = null;
                            });
                            try {
                              final res = await ApiService.instance.testModioApiKey(k);
                              setDialogState(() {
                                testSuccess = res['success'] == true;
                                testMessage = res['message'] ?? (testSuccess! ? l10n.modioTestSuccess : l10n.modioTestFailed);
                              });
                            } catch (e) {
                              setDialogState(() {
                                testSuccess = false;
                                testMessage = '${l10n.modioTestFailed}: $e';
                              });
                            } finally {
                              setDialogState(() => testing = false);
                            }
                          },
                          child: Text(l10n.modioTestConnection),
                        ),
                        const SizedBox(width: 12),
                        SquircleButton(
                          variant: ButtonVariant.primary,
                          icon: const Icon(Icons.save_rounded, size: 16),
                          isLoading: saving,
                          onPressed: () async {
                            final k = keyCtrl.text.trim();
                            setDialogState(() => saving = true);
                            try {
                              await ApiService.instance.saveModioConfig(k);
                              _modioApiKey = k;
                              _modioConfigured = k.isNotEmpty;
                              if (mounted) {
                                setState(() {});
                                _showToast(l10n.modioSaveSuccess);
                              }
                              if (dialogCtx.mounted) {
                                Navigator.of(dialogCtx).pop();
                              }
                            } catch (e) {
                              setDialogState(() {
                                testSuccess = false;
                                testMessage = '${l10n.saveFailed}: $e';
                                saving = false;
                              });
                            }
                          },
                          child: Text(l10n.save),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openModUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (mounted) {
          _showToast('Failed to open link: $e', isError: true);
        }
      }
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
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            title: l10n.modsTitle,
            subtitle: '${l10n.modsSharedNotice} (${l10n.enabledModsRatio(_mods.where((m) => m.enabled).length, _mods.length)})',
            actions: [
              CurrentInstanceBadge(onInstanceChanged: _loadMods),
              SquircleButton(
                variant: ButtonVariant.secondary,
                icon: const Icon(Icons.vpn_key_rounded, size: 16),
                onPressed: _openModioConfigDialog,
                child: Text(l10n.modioConfig),
              ),
              SquircleButton(
                variant: ButtonVariant.secondary,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                onPressed: _loadMods,
                child: Text(l10n.refresh),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Downloader / Installer Card
          CommonCard(
            title: l10n.installMod,
            leading: IconWell(
              icon: Icon(
                Icons.download_for_offline_rounded,
                color: primaryColor,
                size: 18,
              ),
              size: 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: _openModioConfigDialog,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusBadge(
                              label: _modioConfigured ? l10n.modioConfigured : l10n.modioNotConfigured,
                              type: _modioConfigured ? BadgeType.success : BadgeType.warning,
                              icon: Icon(
                                _modioConfigured ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                size: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _modioConfigured ? l10n.modioClickToEdit : l10n.modioClickToConfigure,
                              style: AppTextStyle.caption1.of(
                                context,
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: SurfaceLevel.block.colorOf(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? AppColors.dividerHairlineDark : AppColors.dividerHairlineLight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.tips_and_updates_outlined,
                        size: 16,
                        color: isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.modInstallSteamNotice,
                          style: AppTextStyle.caption1.of(
                            context,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 600;
                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _inputCtrl,
                            decoration: InputDecoration(
                              hintText: l10n.modIdOrUrl,
                              prefixIcon: const Icon(Icons.link_rounded, size: 18),
                            ),
                            onSubmitted: (_) => _installMod(),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: SquircleButton(
                                  variant: ButtonVariant.primary,
                                  icon: const Icon(Icons.cloud_download_rounded, size: 16),
                                  isLoading: _installing,
                                  onPressed: _installMod,
                                  child: Text(l10n.installMod),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SquircleButton(
                                  variant: ButtonVariant.secondary,
                                  icon: const Icon(Icons.upload_file_rounded, size: 16),
                                  isLoading: _uploading,
                                  onPressed: _onUploadZip,
                                  child: Text(l10n.uploadModZip),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inputCtrl,
                            decoration: InputDecoration(
                              hintText: l10n.modIdOrUrl,
                              prefixIcon: const Icon(Icons.link_rounded, size: 18),
                            ),
                            onSubmitted: (_) => _installMod(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SquircleButton(
                          variant: ButtonVariant.primary,
                          icon: const Icon(Icons.cloud_download_rounded, size: 16),
                          isLoading: _installing,
                          onPressed: _installMod,
                          child: Text(l10n.installMod),
                        ),
                        const SizedBox(width: 8),
                        SquircleButton(
                          variant: ButtonVariant.secondary,
                          icon: const Icon(Icons.upload_file_rounded, size: 16),
                          isLoading: _uploading,
                          onPressed: _onUploadZip,
                          child: Text(l10n.uploadModZip),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Notice banner: shared mods repo with independent instance state
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (isDark ? AppColors.primaryDark : AppColors.primaryLight).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (isDark ? AppColors.primaryDark : AppColors.primaryLight).withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.sharedModsNotice,
                    style: AppTextStyle.caption1.of(
                      context,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Installed Mods Card List
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (_mods.isEmpty)
            CommonCard(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Center(
                child: Column(
                  children: [
                    IconWell(
                      icon: Icon(
                        Icons.extension_off_rounded,
                        size: 32,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.noMods,
                      style: AppTextStyle.headline.of(context, emphasized: true),
                    ),
                  ],
                ),
              ),
            )
          else
            CommonCard(
              padding: EdgeInsets.zero,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _mods.length,
                separatorBuilder: (context, index) => const ListRowSeparator(),
                itemBuilder: (context, index) {
                  final mod = _mods[index];

                  // Construct subtitle with details
                  final metaParts = <String>[];
                  if (mod.version.isNotEmpty) metaParts.add('v${mod.version}');
                  if (mod.author.isNotEmpty) metaParts.add('${l10n.modAuthor}: ${mod.author}');
                  metaParts.add(mod.formattedSize);
                  metaParts.add('ID: ${mod.id}');
                  final metaString = metaParts.join('  •  ');

                  final String subtitleText = mod.description.isNotEmpty
                      ? '$metaString\n${mod.description}'
                      : metaString;

                  return ListRow(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    icon: Icon(
                      Icons.extension_rounded,
                      color: mod.enabled ? primaryColor : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                      size: 20,
                    ),
                    title: mod.name,
                    titleWidget: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            mod.name,
                            style: AppTextStyle.body.of(context, emphasized: true),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildSourceBadge(mod.source, isDark, l10n),
                      ],
                    ),
                    subtitle: subtitleText,
                    onTap: () => _toggleMod(mod, !mod.enabled),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (mod.hasWebPage) ...[
                          IconButton(
                            icon: const Icon(Icons.open_in_new_rounded, size: 18),
                            tooltip: l10n.viewModPage,
                            visualDensity: VisualDensity.compact,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            onPressed: () => _openModUrl(mod.sourceUrl),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (mod.canUpdate) ...[
                          SquircleButton(
                            variant: ButtonVariant.secondary,
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            isLoading: _updatingModId == mod.id,
                            icon: const Icon(Icons.sync_rounded, size: 14),
                            onPressed: _updatingModId != null ? null : () => _updateMod(mod),
                            child: Text(l10n.updateMod),
                          ),
                          const SizedBox(width: 8),
                        ],
                        StatusBadge(
                          label: mod.enabled ? l10n.modEnabledForInstance : l10n.modDisabledForInstance,
                          type: mod.enabled ? BadgeType.success : BadgeType.neutral,
                        ),
                        const SizedBox(width: 12),
                        ElasticSwitch(
                          value: mod.enabled,
                          onChanged: (v) => _toggleMod(mod, v),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: isDark ? AppColors.stateDestructiveDark : AppColors.stateDestructive,
                          ),
                          tooltip: l10n.delete,
                          onPressed: () => _deleteMod(mod),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
