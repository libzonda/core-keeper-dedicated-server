import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/instance_item.dart';
import '../services/api_service.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'app_dialog.dart';
import 'app_toast.dart';
import 'pulsing_dot.dart';
import 'squircle_button.dart';
import 'status_badge.dart';

class InstanceManagerDialog extends StatefulWidget {
  final VoidCallback onInstanceChanged;

  const InstanceManagerDialog({
    super.key,
    required this.onInstanceChanged,
  });

  static Future<void> show(BuildContext context, {required VoidCallback onInstanceChanged}) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'InstanceManager',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      pageBuilder: (ctx, anim, _) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 580,
              constraints: const BoxConstraints(maxHeight: 650),
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              decoration: ShapeDecoration(
                color: Theme.of(ctx).brightness == Brightness.dark
                    ? AppColors.surfaceBlockDark
                    : AppColors.surfaceCardLight,
                shape: AppShape.alert,
                shadows: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: Theme.of(ctx).brightness == Brightness.dark ? 0.5 : 0.18),
                    blurRadius: 36,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: InstanceManagerDialog(onInstanceChanged: onInstanceChanged),
            ),
          ),
        );
      },
    );
  }

  static Future<bool> openCreateInstanceDialog(
    BuildContext context, {
    int existingCount = 0,
    List<InstanceItem> instances = const [],
  }) async {
    final l10n = context.l10n;
    int nextPort = 27015 + (existingCount * 10);
    for (final i in instances) {
      if (i.port >= nextPort) nextPort = i.port + 10;
    }
    final nameCtrl = TextEditingController(text: '${l10n.defaultInstanceName} ${existingCount + 1}');
    final portCtrl = TextEditingController(text: '$nextPort');
    final maxPlayersCtrl = TextEditingController(text: '10');
    final passwordCtrl = TextEditingController();
    String netMode = 'sdr';
    bool autoStart = true;

    final ok = await showAppDialog(
      context: context,
      title: l10n.newInstance,
      content: '',
      confirmText: l10n.create,
      cancelText: l10n.cancel,
      customBody: StatefulBuilder(
        builder: (ctx, setDlgState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.instanceName, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
            const SizedBox(height: 6),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(hintText: l10n.instanceNameHint),
            ),
            const SizedBox(height: 14),
            Text(l10n.networkMode, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: netMode,
              dropdownColor: SurfaceLevel.card.colorOf(ctx),
              items: [
                DropdownMenuItem(
                  value: 'sdr',
                  child: Text(
                    l10n.sdrOptionDesc,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                DropdownMenuItem(
                  value: 'direct',
                  child: Text(
                    l10n.directOptionDesc,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
              onChanged: (v) {
                if (v != null) setDlgState(() => netMode = v);
              },
            ),
            const SizedBox(height: 14),
            Text(l10n.serverPort, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
            const SizedBox(height: 6),
            TextField(
              controller: portCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '$nextPort',
                helperText: l10n.portSpacingHint,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.maxPlayers, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: maxPlayersCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: '10'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.serverPasswordOptional, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: passwordCtrl,
                        decoration: InputDecoration(hintText: l10n.directOnlyHint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.autoStartOnBoot, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
                    Text(l10n.autoStartOnBootDesc, style: AppTextStyle.caption2.of(ctx)),
                  ],
                ),
                Switch(
                  value: autoStart,
                  onChanged: (v) => setDlgState(() => autoStart = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final name = nameCtrl.text.trim().isEmpty ? '${l10n.defaultInstanceName} ${existingCount + 1}' : nameCtrl.text.trim();
      final port = int.tryParse(portCtrl.text.trim()) ?? nextPort;
      final maxPlayers = int.tryParse(maxPlayersCtrl.text.trim()) ?? 10;
      final password = passwordCtrl.text.trim();

      try {
        await ApiService.instance.createInstance({
          'name': name,
          'networkMode': netMode,
          'port': port,
          'maxPlayers': maxPlayers,
          'password': password,
          'autoStart': autoStart,
          'worldName': l10n.defaultWorldName,
          'worldIndex': 0,
          'worldMode': 0,
          'worldSeed': 0,
        });
        return true;
      } catch (e) {
        if (context.mounted) {
          showAppToast(context, '${l10n.actionFailed}: $e', type: ToastType.error);
        }
      }
    }
    return false;
  }

  static Future<bool> openEditInstanceDialog(BuildContext context, InstanceItem inst) async {
    final l10n = context.l10n;
    final nameCtrl = TextEditingController(text: inst.name);
    final portCtrl = TextEditingController(text: '${inst.port}');
    final maxPlayersCtrl = TextEditingController(text: '${inst.maxPlayers}');
    final passwordCtrl = TextEditingController(text: inst.password);
    String netMode = inst.networkMode;
    bool autoStart = inst.autoStart;

    final ok = await showAppDialog(
      context: context,
      title: '${l10n.editInstance}: ${inst.name}',
      content: '',
      confirmText: l10n.save,
      cancelText: l10n.cancel,
      customBody: StatefulBuilder(
        builder: (ctx, setDlgState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.instanceName, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
            const SizedBox(height: 6),
            TextField(controller: nameCtrl),
            const SizedBox(height: 14),
            Text(l10n.networkMode, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: netMode,
              dropdownColor: SurfaceLevel.card.colorOf(ctx),
              items: [
                DropdownMenuItem(
                  value: 'sdr',
                  child: Text(
                    l10n.sdrOptionDesc,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                DropdownMenuItem(
                  value: 'direct',
                  child: Text(
                    l10n.directOptionDesc,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
              onChanged: (v) {
                if (v != null) setDlgState(() => netMode = v);
              },
            ),
            const SizedBox(height: 14),
            Text(l10n.serverPort, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
            const SizedBox(height: 6),
            TextField(controller: portCtrl, keyboardType: TextInputType.number),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.maxPlayers, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
                      const SizedBox(height: 6),
                      TextField(controller: maxPlayersCtrl, keyboardType: TextInputType.number),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.serverPasswordOptional, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
                      const SizedBox(height: 6),
                      TextField(controller: passwordCtrl),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.autoStartOnBoot, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
                Switch(
                  value: autoStart,
                  onChanged: (v) => setDlgState(() => autoStart = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      try {
        await ApiService.instance.updateInstance(inst.id, {
          'name': nameCtrl.text.trim(),
          'networkMode': netMode,
          'port': int.tryParse(portCtrl.text.trim()) ?? inst.port,
          'maxPlayers': int.tryParse(maxPlayersCtrl.text.trim()) ?? inst.maxPlayers,
          'password': passwordCtrl.text.trim(),
          'autoStart': autoStart,
        });
        return true;
      } catch (e) {
        if (context.mounted) {
          showAppToast(context, '${l10n.actionFailed}: $e', type: ToastType.error);
        }
      }
    }
    return false;
  }

  static Future<bool> openDeleteInstanceDialog(BuildContext context, InstanceItem inst) async {
    final l10n = context.l10n;
    if (inst.isRunning || inst.isStarting) {
      showAppToast(context, l10n.cannotDeleteRunningInstance, type: ToastType.warning);
      return false;
    }

    final ok = await showAppDialog(
      context: context,
      title: l10n.confirmDeleteInstanceTitle,
      content: l10n.confirmDeleteInstanceDesc,
      isDestructive: true,
      confirmText: l10n.confirm,
    );

    if (ok == true) {
      try {
        await ApiService.instance.deleteInstance(inst.id);
        return true;
      } catch (e) {
        if (context.mounted) {
          showAppToast(context, '${l10n.actionFailed}: $e', type: ToastType.error);
        }
      }
    }
    return false;
  }

  @override
  State<InstanceManagerDialog> createState() => _InstanceManagerDialogState();
}

class _InstanceManagerDialogState extends State<InstanceManagerDialog> {
  List<InstanceItem> _instances = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInstances();
  }

  Future<void> _loadInstances() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.instance.getInstances();
      if (mounted) {
        setState(() {
          _instances = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _switchInstance(InstanceItem inst) async {
    final l10n = context.l10n;
    try {
      await ApiService.instance.switchInstance(inst.id);
      widget.onInstanceChanged();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '${l10n.actionFailed}: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _startInstance(InstanceItem inst) async {
    final l10n = context.l10n;
    try {
      await ApiService.instance.startInstance(inst.id);
      _loadInstances();
      widget.onInstanceChanged();
    } catch (e) {
      if (mounted) {
        showAppToast(context, '${l10n.actionFailed}: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _stopInstance(InstanceItem inst) async {
    final l10n = context.l10n;
    try {
      await ApiService.instance.stopInstance(inst.id);
      _loadInstances();
      widget.onInstanceChanged();
    } catch (e) {
      if (mounted) {
        showAppToast(context, '${l10n.actionFailed}: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _openCreateInstanceDialog() async {
    final ok = await InstanceManagerDialog.openCreateInstanceDialog(
      context,
      existingCount: _instances.length,
      instances: _instances,
    );
    if (ok) {
      _loadInstances();
      widget.onInstanceChanged();
    }
  }

  Future<void> _openEditInstanceDialog(InstanceItem inst) async {
    final ok = await InstanceManagerDialog.openEditInstanceDialog(context, inst);
    if (ok) {
      _loadInstances();
      widget.onInstanceChanged();
    }
  }

  Future<void> _deleteInstance(InstanceItem inst) async {
    final ok = await InstanceManagerDialog.openDeleteInstanceDialog(context, inst);
    if (ok) {
      final list = await ApiService.instance.getInstances();
      widget.onInstanceChanged();
      if (mounted) {
        if (list.isEmpty) {
          Navigator.of(context, rootNavigator: true).pop();
        } else {
          _loadInstances();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.primaryDark : AppColors.primaryLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: ShapeDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  shape: AppShape.sm,
                ),
                child: Icon(Icons.dns_rounded, color: primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.serverManagerTitle,
                      style: AppTextStyle.headline.of(context, emphasized: true),
                    ),
                    Text(
                      l10n.serverManagerDesc,
                      style: AppTextStyle.caption2.of(context),
                    ),
                  ],
                ),
              ),
              SquircleButton(
                variant: ButtonVariant.primary,
                icon: const Icon(Icons.add_rounded, size: 16),
                onPressed: _openCreateInstanceDialog,
                child: Text(l10n.newInstance),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 18,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Instance List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${l10n.loadFailed}: $_error', style: const TextStyle(color: Colors.redAccent)),
                            const SizedBox(height: 8),
                            SquircleButton(
                              variant: ButtonVariant.secondary,
                              onPressed: _loadInstances,
                              child: Text(l10n.retry),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _instances.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final inst = _instances[index];
                          final isCurrent = inst.id == ApiService.instance.currentInstanceId;

                          BadgeType badgeType = BadgeType.neutral;
                          String badgeLabel = l10n.instanceStopped;
                          if (inst.isRunning) {
                            badgeType = BadgeType.success;
                            badgeLabel = l10n.instanceRunning;
                          } else if (inst.isStarting) {
                            badgeType = BadgeType.warning;
                            badgeLabel = l10n.instanceStarting;
                          } else if (inst.isUpdating) {
                            badgeType = BadgeType.warning;
                            badgeLabel = l10n.updating;
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: ShapeDecoration(
                              color: isCurrent
                                  ? primaryColor.withValues(alpha: isDark ? 0.08 : 0.05)
                                  : SurfaceLevel.inset.colorOf(context),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.brMd,
                                side: BorderSide(
                                  color: isCurrent
                                      ? primaryColor.withValues(alpha: 0.35)
                                      : (isDark ? AppColors.dividerHairlineDark : AppColors.dividerHairlineLight),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                PulsingDot(
                                  color: inst.isRunning
                                      ? (isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight)
                                      : (inst.isStarting
                                          ? (isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight)
                                          : Colors.grey),
                                  isPulsing: inst.isRunning || inst.isStarting,
                                  size: 10,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            inst.name,
                                            style: AppTextStyle.subheadline.of(context, emphasized: true),
                                          ),
                                          const SizedBox(width: 8),
                                          StatusBadge(label: badgeLabel, type: badgeType),
                                          if (isCurrent) ...[
                                            const SizedBox(width: 6),
                                            StatusBadge(label: l10n.currentManaging, type: BadgeType.primary),
                                          ],
                                          if (inst.restartRequired) ...[
                                            const SizedBox(width: 6),
                                            StatusBadge(label: l10n.instanceRestartRequired, type: BadgeType.warning),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${l10n.specNetwork}: ${inst.networkMode.toUpperCase()}  •  ${l10n.specPort}: ${inst.port}  •  ${l10n.specMods}: ${l10n.enabledModsRatio(inst.enabledModsCount, inst.totalModsCount)}${inst.uptimeSec > 0 ? '  •  ${l10n.specUptime}: ${inst.formattedUptime}' : ''}',
                                        style: AppTextStyle.caption2.of(context),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Start / Stop
                                if (inst.isRunning || inst.isStarting)
                                  SquircleButton(
                                    variant: ButtonVariant.destructive,
                                    height: 32,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    icon: const Icon(Icons.stop_rounded, size: 14),
                                    onPressed: () => _stopInstance(inst),
                                    child: Text(l10n.stopServer),
                                  )
                                else
                                  SquircleButton(
                                    variant: ButtonVariant.secondary,
                                    height: 32,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    icon: const Icon(Icons.play_arrow_rounded, size: 14),
                                    onPressed: () => _startInstance(inst),
                                    child: Text(l10n.startServer),
                                  ),
                                const SizedBox(width: 6),

                                // Switch to manage
                                if (!isCurrent)
                                  SquircleButton(
                                    variant: ButtonVariant.primary,
                                    height: 32,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    onPressed: () => _switchInstance(inst),
                                    child: Text(l10n.switchInstance),
                                  ),

                                // Edit
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  tooltip: l10n.editInstance,
                                  splashRadius: 18,
                                  onPressed: () => _openEditInstanceDialog(inst),
                                ),

                                // Delete
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                  tooltip: l10n.deleteInstance,
                                  splashRadius: 18,
                                  color: Colors.redAccent,
                                  onPressed: () => _deleteInstance(inst),
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
