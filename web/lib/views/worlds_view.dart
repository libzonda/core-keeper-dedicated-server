import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/world_item.dart';
import '../services/api_service.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import '../utils/file_picker_helper.dart';
import '../widgets/app_dialog.dart';
import '../widgets/common_card.dart';
import '../widgets/current_instance_badge.dart';
import '../widgets/icon_well.dart';
import '../widgets/list_row.dart';
import '../widgets/page_header.dart';
import '../widgets/restart_prompt.dart';
import '../widgets/squircle_button.dart';
import '../widgets/status_badge.dart';

class WorldsView extends StatefulWidget {
  final VoidCallback onWorldChanged;

  const WorldsView({super.key, required this.onWorldChanged});

  @override
  State<WorldsView> createState() => _WorldsViewState();
}

class _WorldsViewState extends State<WorldsView> {
  List<WorldItem> _worlds = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWorlds();
  }

  Future<void> _loadWorlds() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.instance.getWorlds();
      list.sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
      setState(() => _worlds = list);
    } catch (e) {
      _showToast('Failed to load worlds: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchWorld(WorldItem world) async {
    final l10n = context.l10n;
    final ok = await showAppDialog(
      context: context,
      title: l10n.switchWorldConfirm(world.name),
      content: l10n.switchWorldDesc,
      confirmText: l10n.confirm,
    );

    if (ok == true) {
      try {
        await ApiService.instance.switchWorld(world.index);
        _showToast(l10n.switchWorldConfirm(world.name));
        widget.onWorldChanged();
        _loadWorlds();
        if (mounted) {
          await checkAndPromptRestart(
            context,
            title: l10n.restartPromptTitle,
            reason: l10n.restartPromptReason,
          );
        }
      } catch (e) {
        _showToast('Switch Failed: $e', isError: true);
      }
    }
  }

  String _getModeLabel(int mode, AppLocalizations l10n) {
    switch (mode) {
      case 1:
        return l10n.modeHard;
      case 2:
        return l10n.modeCreative;
      case 4:
        return l10n.modeCasual;
      case 0:
      default:
        return l10n.modeNormal;
    }
  }

  Future<void> _openCreateWorldDialog() async {
    final l10n = context.l10n;
    final nameCtrl = TextEditingController(text: '${l10n.newWorldPrefix} ${_worlds.length + 1}');
    final seedCtrl = TextEditingController(text: '0');
    int mode = 0; // Normal

    final ok = await showAppDialog(
      context: context,
      title: l10n.createWorld,
      content: '',
      confirmText: l10n.confirm,
      cancelText: l10n.cancel,
      customBody: StatefulBuilder(
        builder: (ctx, setDlgState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.worldName, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
            const SizedBox(height: 6),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(hintText: l10n.worldName),
            ),
            const SizedBox(height: 14),
            Text(l10n.worldMode, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: mode,
              dropdownColor: SurfaceLevel.card.colorOf(ctx),
              items: [
                DropdownMenuItem(value: 0, child: Text(l10n.modeNormal)),
                DropdownMenuItem(value: 1, child: Text(l10n.modeHard)),
                DropdownMenuItem(value: 2, child: Text(l10n.modeCreative)),
                DropdownMenuItem(value: 4, child: Text(l10n.modeCasual)),
              ],
              onChanged: (v) {
                if (v != null) setDlgState(() => mode = v);
              },
            ),
            const SizedBox(height: 14),
            Text(l10n.worldSeed, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
            const SizedBox(height: 6),
            TextField(
              controller: seedCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: l10n.randomSeedHint),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final name = nameCtrl.text.trim().isEmpty ? '${l10n.newWorldPrefix} ${_worlds.length + 1}' : nameCtrl.text.trim();
      final seed = int.tryParse(seedCtrl.text.trim()) ?? 0;

      try {
        await ApiService.instance.createWorld(
          name: name,
          seed: seed,
          mode: mode,
        );
        _showToast(l10n.createWorldSuccess);
        _loadWorlds();
      } catch (e) {
        _showToast('Create Failed: $e', isError: true);
      }
    }
  }

  void _exportWorld(WorldItem world) {
    final l10n = context.l10n;
    if (!world.exists || world.sizeBytes <= 0) {
      _showToast(l10n.worldFileNotGenerated, isError: true);
      return;
    }
    final url = ApiService.instance.getWorldExportUrl(world.index);
    final filename = '${world.name.isEmpty ? 'world_${world.index}' : world.name}.zip';
    downloadFile(url, filename);
    _showToast('${l10n.exportWorld}: $filename');
  }

  void _handleImportWorld() {
    final l10n = context.l10n;
    pickWorldFile((bytes, filename) async {
      if (bytes.isEmpty) {
        _showToast(l10n.selectedFileEmpty, isError: true);
        return;
      }

      String defaultName = filename;
      for (final ext in ['.world.gzip', '.world', '.gzip', '.zip']) {
        if (defaultName.toLowerCase().endsWith(ext)) {
          defaultName = defaultName.substring(0, defaultName.length - ext.length);
        }
      }
      if (defaultName.isEmpty) defaultName = l10n.importedWorldDefault;

      final nameCtrl = TextEditingController(text: defaultName);
      int mode = 0;

      final ok = await showAppDialog(
        context: context,
        title: l10n.importWorldTitle,
        content: '',
        confirmText: l10n.importWorld,
        cancelText: l10n.cancel,
        customBody: StatefulBuilder(
          builder: (ctx, setDlgState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l10n.selectedFile}: $filename (${(bytes.length / 1024).toStringAsFixed(1)} KB)',
                style: AppTextStyle.caption1.of(
                  ctx,
                  color: Theme.of(ctx).brightness == Brightness.dark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 14),
              Text(l10n.worldName, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
              const SizedBox(height: 6),
              TextField(controller: nameCtrl),
              const SizedBox(height: 14),
              Text(l10n.worldMode, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                initialValue: mode,
                dropdownColor: SurfaceLevel.card.colorOf(ctx),
                items: [
                  DropdownMenuItem(value: 0, child: Text(l10n.modeNormal)),
                  DropdownMenuItem(value: 1, child: Text(l10n.modeHard)),
                  DropdownMenuItem(value: 2, child: Text(l10n.modeCreative)),
                  DropdownMenuItem(value: 4, child: Text(l10n.modeCasual)),
                ],
                onChanged: (v) {
                  if (v != null) setDlgState(() => mode = v);
                },
              ),
            ],
          ),
        ),
      );

      if (ok == true) {
        final name = nameCtrl.text.trim().isEmpty ? defaultName : nameCtrl.text.trim();
        try {
          await ApiService.instance.importWorld(
            fileBytes: bytes,
            filename: filename,
            name: name,
            mode: mode,
          );
          _showToast(l10n.importWorldSuccess);
          _loadWorlds();
        } catch (e) {
          _showToast('Import Failed: $e', isError: true);
        }
      }
    });
  }

  Future<void> _deleteWorld(WorldItem world) async {
    final l10n = context.l10n;
    final ok = await showAppDialog(
      context: context,
      title: '${l10n.delete} ${world.name}?',
      content: l10n.confirmDeleteModDesc,
      confirmText: l10n.delete,
      isDestructive: true,
    );

    if (ok == true) {
      try {
        await ApiService.instance.deleteWorld(world.index);
        _showToast('${l10n.delete}: ${world.name}');
        _loadWorlds();
      } catch (e) {
        _showToast('Delete Failed: $e', isError: true);
      }
    }
  }

  Future<void> _renameWorld(WorldItem world) async {
    final l10n = context.l10n;
    final currentName = world.name.isEmpty ? l10n.defaultWorldName : world.name;
    final nameCtrl = TextEditingController(text: currentName);

    final ok = await showAppDialog(
      context: context,
      title: '${l10n.renameWorldTitle}: #${world.index}',
      content: '',
      confirmText: l10n.save,
      cancelText: l10n.cancel,
      customBody: StatefulBuilder(
        builder: (ctx, setDlgState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.worldName, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
            const SizedBox(height: 6),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.worldNameInputHint,
              ),
            ),
            if (world.isActive) ...[
              const SizedBox(height: 12),
              Text(
                l10n.worldRenameRestartNotice,
                style: AppTextStyle.caption2.of(ctx, color: Colors.amberAccent),
              ),
            ],
          ],
        ),
      ),
    );

    if (ok == true) {
      final newName = nameCtrl.text.trim();
      if (newName.isEmpty) return;
      try {
        await ApiService.instance.renameWorld(world.index, newName);
        _showToast(world.isActive
            ? '${l10n.worldRenamedSuccess} (${l10n.instanceRestartRequired})'
            : l10n.worldRenamedSuccess);
        _loadWorlds();
      } catch (e) {
        _showToast('${l10n.actionFailed}: $e', isError: true);
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = context.l10n;
    final primaryColor = isDark ? AppColors.primaryDark : AppColors.primaryLight;

    final activeWorld = _worlds.where((w) => w.isActive).firstOrNull;

    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          PageHeader(
            title: l10n.worldsTitle,
            subtitle: l10n.worldsSubtitle,
            actions: [
              CurrentInstanceBadge(onInstanceChanged: _loadWorlds),
              SquircleButton(
                variant: ButtonVariant.primary,
                icon: const Icon(Icons.add_rounded, size: 16),
                onPressed: _openCreateWorldDialog,
                child: Text(l10n.createWorld),
              ),
              SquircleButton(
                variant: ButtonVariant.secondary,
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                onPressed: _handleImportWorld,
                child: Text(l10n.importWorld),
              ),
              SquircleButton(
                variant: ButtonVariant.secondary,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                onPressed: _loadWorlds,
                child: Text(l10n.refresh),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Active World Hero Card
          if (activeWorld != null) ...[
            CommonCard(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  IconWell(
                    icon: Icon(Icons.public_rounded, color: primaryColor, size: 28),
                    size: 52,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            StatusBadge(label: l10n.activeBadge, type: BadgeType.success),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                activeWorld.name.isEmpty ? l10n.defaultWorldName : activeWorld.name,
                                style: AppTextStyle.headline.of(context, emphasized: true),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: l10n.renameWorld,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _renameWorld(activeWorld),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_getModeLabel(activeWorld.mode, l10n)}  •  ${activeWorld.formattedSizeWith(activeWorld.isActive ? l10n.worldActivePendingPlayer : l10n.worldNotGenerated)}${activeWorld.formattedCreatedAt.isNotEmpty ? '  •  ${l10n.worldCreatedAt}: ${activeWorld.formattedCreatedAt}' : ''}',
                          style: AppTextStyle.caption1.of(
                            context,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            tabular: true,
                          ),
                        ),
                        if (!activeWorld.exists) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: (isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 14,
                                  color: isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    l10n.worldPendingGenerationTip,
                                    style: AppTextStyle.caption2.of(
                                      context,
                                      color: isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (activeWorld.exists && activeWorld.sizeBytes > 0)
                    SquircleButton(
                      variant: ButtonVariant.secondary,
                      icon: const Icon(Icons.download_rounded, size: 16),
                      onPressed: () => _exportWorld(activeWorld),
                      child: Text(l10n.exportWorld),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Worlds List
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else
            CommonCard(
              padding: EdgeInsets.zero,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _worlds.length,
                separatorBuilder: (context, index) => const ListRowSeparator(),
                itemBuilder: (context, index) {
                  final world = _worlds[index];
                  return ListRow(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    icon: Icon(
                      Icons.folder_open_rounded,
                      color: world.isActive ? primaryColor : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                      size: 20,
                    ),
                    title: world.name.isEmpty ? l10n.defaultWorldName : world.name,
                    subtitle: '${_getModeLabel(world.mode, l10n)}  •  ${world.formattedSizeWith(world.isActive ? l10n.worldActivePendingPlayer : l10n.worldNotGenerated)}${world.formattedCreatedAt.isNotEmpty ? '  •  ${l10n.worldCreatedAt}: ${world.formattedCreatedAt}' : ''}${world.seed != 0 ? '  •  ${l10n.worldSeed}: ${world.seed}' : ''}',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: l10n.renameWorld,
                          onPressed: () => _renameWorld(world),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            Icons.download_rounded,
                            size: 18,
                            color: (world.exists && world.sizeBytes > 0)
                                ? (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)
                                : (isDark ? AppColors.textSecondaryDark.withValues(alpha: 0.4) : AppColors.textSecondaryLight.withValues(alpha: 0.4)),
                          ),
                          tooltip: (world.exists && world.sizeBytes > 0) ? l10n.exportWorld : l10n.worldFileNotGenerated,
                          onPressed: () => _exportWorld(world),
                        ),
                        const SizedBox(width: 4),
                        if (world.isActive)
                          StatusBadge(label: l10n.activeBadge, type: BadgeType.success)
                        else
                          SquircleButton(
                            variant: ButtonVariant.secondary,
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            onPressed: () => _switchWorld(world),
                            child: Text(l10n.switchToWorld),
                          ),
                        const SizedBox(width: 8),
                        if (!world.isActive)
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: isDark ? AppColors.stateDestructiveDark : AppColors.stateDestructive,
                            ),
                            tooltip: l10n.delete,
                            onPressed: () => _deleteWorld(world),
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
