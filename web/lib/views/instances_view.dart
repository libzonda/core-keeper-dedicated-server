import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import '../models/instance_item.dart';
import '../services/api_service.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import '../widgets/app_dialog.dart';
import '../widgets/common_card.dart';
import '../widgets/icon_well.dart';
import '../widgets/instance_manager_dialog.dart';
import '../widgets/pulsing_dot.dart';
import '../widgets/squircle_button.dart';
import '../widgets/status_badge.dart';

class InstancesView extends StatefulWidget {
  final VoidCallback onInstanceChanged;

  const InstancesView({
    super.key,
    required this.onInstanceChanged,
  });

  @override
  State<InstancesView> createState() => _InstancesViewState();
}

class _InstancesViewState extends State<InstancesView> {
  List<InstanceItem> _instances = [];
  bool _loading = true;
  String? _busyInstanceId;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadInstances();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollInstances();
    });
  }

  Future<void> _pollInstances() async {
    try {
      final list = await ApiService.instance.getInstances();
      if (mounted) {
        setState(() => _instances = list);
      }
    } catch (_) {}
  }

  Future<void> _loadInstances() async {
    if (_instances.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      final list = await ApiService.instance.getInstances();
      if (mounted) {
        setState(() => _instances = list);
      }
    } catch (e) {
      if (mounted && _instances.isEmpty) {
        final l10n = mounted ? context.l10n : null;
        _showToast(l10n != null ? '${l10n.loadFailed}: $e' : 'Failed: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.teal,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _switchActive(InstanceItem inst) async {
    final l10n = context.l10n;
    try {
      await ApiService.instance.switchInstance(inst.id);
      _showToast(l10n.instanceSwitchedSuccess(inst.name));
      await _loadInstances();
      widget.onInstanceChanged();
    } catch (e) {
      _showToast('${l10n.actionFailed}: $e', isError: true);
    }
  }

  Future<void> _startInstance(InstanceItem inst) async {
    final l10n = context.l10n;
    setState(() => _busyInstanceId = inst.id);
    try {
      await ApiService.instance.startInstance(inst.id);
      _showToast('${inst.name}: ${l10n.instanceStarting}');
      await Future.delayed(const Duration(milliseconds: 600));
      await _loadInstances();
      widget.onInstanceChanged();
    } catch (e) {
      _showToast('${l10n.actionFailed}: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busyInstanceId = null);
    }
  }

  Future<void> _stopInstance(InstanceItem inst) async {
    final l10n = context.l10n;
    final ok = await showAppDialog(
      context: context,
      title: l10n.confirmStopTitle,
      content: '${l10n.confirmStopDesc} (${inst.name})',
      isDestructive: true,
      confirmText: l10n.stopServer,
    );
    if (ok != true) return;

    setState(() => _busyInstanceId = inst.id);
    try {
      await ApiService.instance.stopInstance(inst.id);
      _showToast('${inst.name}: ${l10n.instanceStopped}');
      await _loadInstances();
      widget.onInstanceChanged();
    } catch (e) {
      _showToast('${l10n.actionFailed}: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busyInstanceId = null);
    }
  }

  Future<void> _restartInstance(InstanceItem inst) async {
    final l10n = context.l10n;
    setState(() => _busyInstanceId = inst.id);
    try {
      await ApiService.instance.restartInstance(inst.id);
      _showToast('${inst.name}: ${l10n.restartTriggered}');
      await Future.delayed(const Duration(milliseconds: 800));
      await _loadInstances();
      widget.onInstanceChanged();
    } catch (e) {
      _showToast('${l10n.actionFailed}: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busyInstanceId = null);
    }
  }

  // --- Reuse Sidebar's Dialogs ---

  Future<void> _openCreateInstanceDialog() async {
    final l10n = context.l10n;
    final ok = await InstanceManagerDialog.openCreateInstanceDialog(
      context,
      existingCount: _instances.length,
      instances: _instances,
    );
    if (ok) {
      _showToast(l10n.instanceCreatedSuccess);
      await _loadInstances();
      widget.onInstanceChanged();
    }
  }

  Future<void> _openEditInstanceDialog(InstanceItem inst) async {
    final l10n = context.l10n;
    final ok = await InstanceManagerDialog.openEditInstanceDialog(context, inst);
    if (ok) {
      _showToast(l10n.instanceSavedSuccess);
      await _loadInstances();
      widget.onInstanceChanged();
    }
  }

  Future<void> _deleteInstance(InstanceItem inst) async {
    final l10n = context.l10n;
    final ok = await InstanceManagerDialog.openDeleteInstanceDialog(context, inst);
    if (ok) {
      _showToast(l10n.instanceDeletedSuccess);
      await _loadInstances();
      widget.onInstanceChanged();
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    final l10n = context.l10n;
    _showToast('$label ${l10n.copiedToClipboard}');
  }

  BadgeType _getBadgeType(String status) {
    switch (status) {
      case 'running':
        return BadgeType.success;
      case 'starting':
      case 'updating':
        return BadgeType.warning;
      default:
        return BadgeType.neutral;
    }
  }

  String _getStatusText(String status, AppLocalizations l10n) {
    switch (status) {
      case 'running':
        return l10n.instanceRunning;
      case 'starting':
        return l10n.instanceStarting;
      case 'updating':
        return l10n.updating;
      case 'stopping':
        return l10n.instanceStopping;
      default:
        return l10n.instanceStopped;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.primaryDark : AppColors.primaryLight;
    final currentActiveId = ApiService.instance.currentInstanceId;
    final currentActive = _instances.where((i) => i.id == currentActiveId).firstOrNull;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentMinHeight = constraints.maxHeight > 40 ? constraints.maxHeight - 40 : 0.0;
          final isCompact = constraints.maxWidth < 720;
          final isMobile = constraints.maxWidth < 500;

          final titleSection = Row(
            children: [
              IconWell(
                icon: Icon(Icons.dns_rounded, color: primaryColor, size: 24),
                size: 42,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.instancesTitle,
                      style: AppTextStyle.title2.of(context, emphasized: true),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.instancesSubtitle,
                      style: AppTextStyle.caption1.of(
                        context,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final topSwitcherPill = _instances.isNotEmpty
              ? Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: ShapeDecoration(
                    color: SurfaceLevel.inset.colorOf(context),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: (isDark ? AppColors.dividerHairlineDark : AppColors.dividerHairlineLight),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PulsingDot(
                        color: currentActive?.isRunning == true
                            ? (isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight)
                            : (currentActive?.isStarting == true
                                ? (isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight)
                                : Colors.grey),
                        isPulsing: currentActive?.isRunning == true || currentActive?.isStarting == true,
                        size: 7,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${l10n.currentManaging}: ',
                        style: AppTextStyle.caption2.of(
                          context,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        ),
                      ),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: (currentActiveId != null && _instances.any((i) => i.id == currentActiveId))
                              ? currentActiveId
                              : (_instances.isNotEmpty ? _instances.first.id : null),
                          dropdownColor: SurfaceLevel.card.colorOf(context),
                          borderRadius: AppRadius.brMd,
                          icon: const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.unfold_more_rounded, size: 16),
                          ),
                          style: AppTextStyle.caption1.of(context, emphasized: true),
                          items: _instances.map((i) {
                            final mode = i.networkMode == 'sdr' ? 'SDR' : l10n.direct;
                            return DropdownMenuItem<String>(
                              value: i.id,
                              child: Text('${i.name} ($mode • ${i.port})'),
                            );
                          }).toList(),
                          onChanged: (newId) {
                            if (newId != null && newId != currentActiveId) {
                              final target = _instances.firstWhere((i) => i.id == newId);
                              _switchActive(target);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                )
              : null;

          final isButtonCompact = constraints.maxWidth < 960;

          final headerActions = [
            if (topSwitcherPill != null) topSwitcherPill,
            SquircleButton(
              variant: ButtonVariant.secondary,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              tooltip: l10n.refresh,
              onPressed: _loading ? null : _loadInstances,
              child: isButtonCompact ? null : Text(l10n.refresh),
            ),
            SquircleButton(
              variant: ButtonVariant.primary,
              icon: const Icon(Icons.add_rounded, size: 18),
              onPressed: _openCreateInstanceDialog,
              tooltip: l10n.newInstance,
              child: isButtonCompact ? null : Text(l10n.newInstance),
            ),
          ];

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: isMobile ? 16 : 20,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: contentMinHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Responsive Page Header
                    if (isCompact) ...[
                      titleSection,
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: headerActions,
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(child: titleSection),
                          const SizedBox(width: 16),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < headerActions.length; i++) ...[
                                if (i > 0) const SizedBox(width: 8),
                                headerActions[i],
                              ],
                            ],
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Content Area
                    if (_loading && _instances.isEmpty)
                      const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_instances.isEmpty)
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: CommonCard(
                              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    IconWell(
                                      icon: Icon(Icons.dns_rounded, size: 40, color: primaryColor),
                                      size: 72,
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      l10n.noInstancesTitle,
                                      style: AppTextStyle.title3.of(context, emphasized: true),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      l10n.noInstancesDesc,
                                      style: AppTextStyle.body.of(
                                        context,
                                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 28),
                                    SquircleButton(
                                      variant: ButtonVariant.primary,
                                      icon: const Icon(Icons.add_rounded, size: 18),
                                      onPressed: _openCreateInstanceDialog,
                                      child: Text(l10n.createInstance),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _instances.length,
                separatorBuilder: (context, index) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final inst = _instances[index];
                  final isCurrentActive = inst.id == currentActiveId;
                  final isBusy = _busyInstanceId == inst.id;

                  return CommonCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Header Row
                        Row(
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
                            const SizedBox(width: 10),
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      inst.name,
                                      style: AppTextStyle.headline.of(context, emphasized: true),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isCurrentActive) ...[
                                    StatusBadge(label: l10n.currentManaging, type: BadgeType.primary),
                                    const SizedBox(width: 6),
                                  ],
                                  StatusBadge(
                                    label: _getStatusText(inst.status, l10n),
                                    type: _getBadgeType(inst.status),
                                  ),
                                  if (inst.restartRequired) ...[
                                    const SizedBox(width: 6),
                                    StatusBadge(label: l10n.instanceRestartRequired, type: BadgeType.warning),
                                  ],
                                ],
                              ),
                            ),
                            // Action Buttons
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Switch Button
                                if (!isCurrentActive)
                                  SquircleButton(
                                    variant: ButtonVariant.primary,
                                    height: 32,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                                    onPressed: () => _switchActive(inst),
                                    child: Text(l10n.switchInstance),
                                  ),
                                const SizedBox(width: 6),
                                if (inst.isStopped)
                                  SquircleButton(
                                    variant: ButtonVariant.secondary,
                                    height: 32,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    icon: isBusy
                                        ? const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.play_arrow_rounded, size: 16),
                                    onPressed: isBusy ? null : () => _startInstance(inst),
                                    child: Text(l10n.startServer),
                                  )
                                else ...[
                                  SquircleButton(
                                    variant: ButtonVariant.secondary,
                                    height: 32,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    icon: const Icon(Icons.restart_alt_rounded, size: 15),
                                    onPressed: isBusy ? null : () => _restartInstance(inst),
                                    child: Text(l10n.restartServer),
                                  ),
                                  const SizedBox(width: 6),
                                  SquircleButton(
                                    variant: ButtonVariant.destructive,
                                    height: 32,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    icon: const Icon(Icons.stop_rounded, size: 15),
                                    onPressed: isBusy ? null : () => _stopInstance(inst),
                                    child: Text(l10n.stopServer),
                                  ),
                                ],
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.tune_rounded, size: 18),
                                  tooltip: l10n.editInstance,
                                  splashRadius: 18,
                                  onPressed: () => _openEditInstanceDialog(inst),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                  tooltip: l10n.deleteInstance,
                                  splashRadius: 18,
                                  color: Colors.redAccent,
                                  onPressed: () => _deleteInstance(inst),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Instance Specs Grid
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: ShapeDecoration(
                            color: SurfaceLevel.inset.colorOf(context),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.brSm,
                              side: BorderSide(
                                color: (isDark ? AppColors.dividerHairlineDark : AppColors.dividerHairlineLight),
                                width: 0.8,
                              ),
                            ),
                          ),
                          child: Wrap(
                            spacing: 24,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildInfoItem(
                                context,
                                icon: Icons.network_check_rounded,
                                label: l10n.specNetwork,
                                value: inst.networkMode == 'sdr' ? 'Steam SDR' : '${l10n.direct} (Direct)',
                              ),
                              _buildInfoItem(
                                context,
                                icon: Icons.numbers_rounded,
                                label: l10n.specPort,
                                value: '${inst.port}',
                              ),
                              _buildInfoItem(
                                context,
                                icon: Icons.public_rounded,
                                label: l10n.specWorldSlot,
                                value: '#${inst.worldIndex} ${inst.worldName.isNotEmpty ? inst.worldName : l10n.defaultWorldName}',
                              ),
                              _buildInfoItem(
                                context,
                                icon: Icons.extension_rounded,
                                label: l10n.specMods,
                                value: l10n.enabledModsRatio(inst.enabledModsCount, inst.totalModsCount),
                              ),
                              if (inst.isRunning) ...[
                                _buildInfoItem(
                                  context,
                                  icon: Icons.timer_outlined,
                                  label: l10n.specUptime,
                                  value: inst.formattedUptime,
                                ),
                                _buildInfoItem(
                                  context,
                                  icon: Icons.memory_rounded,
                                  label: l10n.specPid,
                                  value: '${inst.pid}',
                                ),
                              ],
                            ],
                          ),
                        ),

                        // SDR Game ID banner if available
                        if (inst.networkMode == 'sdr' && inst.gameId.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: ShapeDecoration(
                              color: primaryColor.withValues(alpha: isDark ? 0.12 : 0.08),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.brSm,
                                side: BorderSide(color: primaryColor.withValues(alpha: 0.3), width: 0.8),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.vpn_key_rounded, size: 16, color: primaryColor),
                                const SizedBox(width: 8),
                                Text(
                                  'Game ID: ',
                                  style: AppTextStyle.caption1.of(context, emphasized: true),
                                ),
                                SelectableText(
                                  inst.gameId,
                                  style: AppTextStyle.caption1.of(context, color: primaryColor, tabular: true),
                                ),
                                const Spacer(),
                                SquircleButton(
                                  variant: ButtonVariant.secondary,
                                  height: 26,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  icon: const Icon(Icons.copy_rounded, size: 13),
                                  onPressed: () => _copyToClipboard(inst.gameId, 'Game ID'),
                                  child: Text(l10n.copyGameId),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
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

  Widget _buildInfoItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: secondaryColor),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: AppTextStyle.caption2.of(context, color: secondaryColor),
        ),
        Text(
          value,
          style: AppTextStyle.caption1.of(context, emphasized: true),
        ),
      ],
    );
  }
}
