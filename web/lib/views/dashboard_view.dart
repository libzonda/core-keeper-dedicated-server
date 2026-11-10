import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/server_status.dart';
import '../services/api_service.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import '../widgets/app_dialog.dart';
import '../widgets/common_card.dart';
import '../widgets/current_instance_badge.dart';
import '../widgets/icon_well.dart';
import '../widgets/list_row.dart';
import '../widgets/page_header.dart';
import '../widgets/pulsing_dot.dart';
import '../widgets/squircle_button.dart';
import '../widgets/status_badge.dart';

class DashboardView extends StatefulWidget {
  final ServerStatus? status;
  final VoidCallback onRefresh;
  final ValueChanged<int> onNavigate;

  const DashboardView({
    super.key,
    required this.status,
    required this.onRefresh,
    required this.onNavigate,
  });

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    widget.onRefresh();
  }

  Future<void> _handleStart() async {
    final l10n = context.l10n;
    setState(() => _actionLoading = true);
    try {
      await ApiService.instance.startServer();
      _showToast(l10n.startingServer);
      widget.onRefresh();
    } catch (e) {
      _showToast('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _handleStop() async {
    final l10n = context.l10n;
    final confirm = await showAppDialog(
      context: context,
      title: l10n.confirmStopTitle,
      content: l10n.confirmStopDesc,
      confirmText: l10n.stopServer,
      isDestructive: true,
    );

    if (confirm != true) return;

    setState(() => _actionLoading = true);
    try {
      await ApiService.instance.stopServer();
      _showToast(l10n.stopServer);
      widget.onRefresh();
    } catch (e) {
      _showToast('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _handleRestart() async {
    final l10n = context.l10n;
    final confirm = await showAppDialog(
      context: context,
      title: l10n.confirmRestartTitle,
      content: l10n.confirmRestartDesc,
      confirmText: l10n.restartServer,
      isDestructive: false,
    );

    if (confirm != true) return;

    setState(() => _actionLoading = true);
    try {
      await ApiService.instance.restartServer();
      _showToast(l10n.restartTriggered);
      widget.onRefresh();
    } catch (e) {
      _showToast('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _handleUpdate() async {
    final l10n = context.l10n;
    final confirm = await showAppDialog(
      context: context,
      title: l10n.confirmUpdateTitle,
      content: l10n.confirmUpdateDesc,
      confirmText: l10n.confirm,
    );

    if (confirm != true) return;

    setState(() => _actionLoading = true);
    try {
      await ApiService.instance.updateServer();
      _showToast(l10n.updateServer);
      widget.onRefresh();
    } catch (e) {
      _showToast('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  void _copyToClipboard(String text, String tip) {
    Clipboard.setData(ClipboardData(text: text));
    _showToast(tip);
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
    final s = widget.status;
    final isRunning = s?.isRunning == true;
    final isSDR = s?.isSDR ?? true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = context.l10n;
    final primaryColor = isDark ? AppColors.primaryDark : AppColors.primaryLight;

    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Row
          PageHeader(
            title: l10n.dashboardTitle,
            subtitle: l10n.dashboardSubtitle,
            actionsBuilder: (context, isCompact) => [
              CurrentInstanceBadge(onInstanceChanged: widget.onRefresh, isCompact: isCompact),
              SquircleButton(
                variant: ButtonVariant.secondary,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                onPressed: widget.onRefresh,
                tooltip: l10n.refresh,
                child: isCompact ? null : Text(l10n.refresh),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // SDR Game ID Hero Banner Card
          if (isSDR)
            CommonCard(
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconWell(
                              icon: Icon(Icons.vpn_key_rounded, color: primaryColor, size: 22),
                              size: 40,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      l10n.gameIdTitle,
                                      style: AppTextStyle.caption1.of(
                                        context,
                                        emphasized: true,
                                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  StatusBadge(
                                    label: isRunning ? l10n.running : (s?.isStarting == true ? l10n.starting : l10n.offline),
                                    type: isRunning ? BadgeType.success : (s?.isStarting == true ? BadgeType.warning : BadgeType.neutral),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          s?.gameId.isNotEmpty == true
                              ? s!.gameId
                              : (s?.isStarting == true
                                  ? l10n.gameIdStartingNotice
                                  : (isRunning ? l10n.gameIdGenerating : l10n.gameIdOfflineNotice)),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            letterSpacing: 1.0,
                            color: s?.gameId.isNotEmpty == true ? primaryColor : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.gameIdTip,
                          style: AppTextStyle.caption2.of(
                            context,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          ),
                        ),
                        if (s?.gameId.isNotEmpty == true) ...[
                          const SizedBox(height: 12),
                          SquircleButton(
                            variant: ButtonVariant.primary,
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            onPressed: () => _copyToClipboard(s!.gameId, l10n.gameIdCopied),
                            child: Text(l10n.copyGameId),
                          ),
                        ],
                      ],
                    )
                  : Row(
                      children: [
                        IconWell(
                          icon: Icon(
                            Icons.vpn_key_rounded,
                            color: primaryColor,
                            size: 24,
                          ),
                          size: 48,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    l10n.gameIdTitle,
                                    style: AppTextStyle.caption1.of(
                                      context,
                                      emphasized: true,
                                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  StatusBadge(
                                    label: isRunning ? l10n.running : (s?.isStarting == true ? l10n.starting : l10n.offline),
                                    type: isRunning ? BadgeType.success : (s?.isStarting == true ? BadgeType.warning : BadgeType.neutral),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                s?.gameId.isNotEmpty == true
                                    ? s!.gameId
                                    : (s?.isStarting == true
                                        ? l10n.gameIdStartingNotice
                                        : (isRunning ? l10n.gameIdGenerating : l10n.gameIdOfflineNotice)),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                  letterSpacing: 1.0,
                                  color: s?.gameId.isNotEmpty == true ? primaryColor : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.gameIdTip,
                                style: AppTextStyle.caption2.of(
                                  context,
                                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        if (s?.gameId.isNotEmpty == true)
                          SquircleButton(
                            variant: ButtonVariant.primary,
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            onPressed: () => _copyToClipboard(s!.gameId, l10n.gameIdCopied),
                            child: Text(l10n.copyGameId),
                          ),
                      ],
                    ),
            )
          else
            CommonCard(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  IconWell(
                    icon: Icon(
                      Icons.lan_rounded,
                      color: isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight,
                      size: 24,
                    ),
                    size: 48,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.directTitle,
                          style: AppTextStyle.caption1.of(
                            context,
                            emphasized: true,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.directPortLabel(s?.port ?? 27015),
                          style: AppTextStyle.headline.of(
                            context,
                            emphasized: true,
                            tabular: true,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.directTip,
                          style: AppTextStyle.caption2.of(
                            context,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Quick Control Actions Card
          CommonCard(
            title: l10n.controlTitle,
            leading: IconWell(
              icon: Icon(
                Icons.bolt_rounded,
                color: primaryColor,
                size: 18,
              ),
              size: 32,
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (s?.isStarting == true) ...[
                  SquircleButton(
                    variant: ButtonVariant.secondary,
                    isLoading: true,
                    onPressed: null,
                    child: Text(l10n.startingServer),
                  ),
                  SquircleButton(
                    variant: ButtonVariant.destructive,
                    icon: const Icon(Icons.stop_rounded),
                    isLoading: _actionLoading,
                    onPressed: _handleStop,
                    child: Text(l10n.stopServer),
                  ),
                  SquircleButton(
                    variant: ButtonVariant.secondary,
                    icon: const Icon(Icons.refresh_rounded),
                    isLoading: _actionLoading,
                    onPressed: _handleRestart,
                    child: Text(l10n.restartServer),
                  ),
                ] else if (_actionLoading && !isRunning)
                  SquircleButton(
                    variant: ButtonVariant.secondary,
                    isLoading: true,
                    onPressed: null,
                    child: Text(l10n.startingServer),
                  )
                else if (isRunning) ...[
                  SquircleButton(
                    variant: ButtonVariant.destructive,
                    icon: const Icon(Icons.stop_rounded),
                    isLoading: _actionLoading,
                    onPressed: _handleStop,
                    child: Text(l10n.stopServer),
                  ),
                  SquircleButton(
                    variant: ButtonVariant.secondary,
                    icon: const Icon(Icons.refresh_rounded),
                    isLoading: _actionLoading,
                    onPressed: _handleRestart,
                    child: Text(l10n.restartServer),
                  ),
                ] else
                  SquircleButton(
                    variant: ButtonVariant.primary,
                    icon: const Icon(Icons.play_arrow_rounded),
                    isLoading: _actionLoading,
                    onPressed: _handleStart,
                    child: Text(l10n.startServer),
                  ),
                SquircleButton(
                  variant: ButtonVariant.secondary,
                  icon: const Icon(Icons.system_update_alt_rounded),
                  isLoading: _actionLoading,
                  onPressed: _handleUpdate,
                  child: Text(l10n.updateServer),
                ),
                SquircleButton(
                  variant: ButtonVariant.ghost,
                  icon: const Icon(Icons.terminal_rounded),
                  onPressed: () => widget.onNavigate(2),
                  child: Text(l10n.viewLogs),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Status Metrics Grid with Tabular Numerics
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              final colWidth = isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(
                    width: colWidth,
                    label: l10n.metricStatus,
                    value: isRunning
                        ? l10n.running.toUpperCase()
                        : (s?.isStarting == true
                            ? l10n.starting.toUpperCase()
                            : (s?.isUpdating == true ? l10n.updating.toUpperCase() : l10n.offline.toUpperCase())),
                    statusType: isRunning ? BadgeType.success : (s?.isUpdating == true ? BadgeType.warning : BadgeType.error),
                    icon: Icons.power_settings_new_rounded,
                    isPulsing: isRunning,
                  ),
                  _MetricCard(
                    width: colWidth,
                    label: l10n.metricMode,
                    value: isSDR ? l10n.sdr : l10n.direct,
                    statusType: isSDR ? BadgeType.primary : BadgeType.warning,
                    icon: Icons.hub_rounded,
                  ),
                  _MetricCard(
                    width: colWidth,
                    label: l10n.metricActiveWorld,
                    value: (s?.worldName != null && s!.worldName.isNotEmpty)
                        ? s.worldName
                        : (s?.serverName != null && s!.serverName.isNotEmpty
                            ? s.serverName
                            : l10n.defaultWorldName),
                    statusType: BadgeType.neutral,
                    icon: Icons.public_rounded,
                  ),
                  _MetricCard(
                    width: colWidth,
                    label: l10n.metricUptime,
                    value: s?.formattedUptime ?? '0s',
                    statusType: BadgeType.neutral,
                    icon: Icons.timer_outlined,
                    tabular: true,
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // Server Details Grouped Card
          CommonCard(
            title: l10n.dashboardOverviewTitle,
            leading: IconWell(
              icon: Icon(
                Icons.dns_rounded,
                color: primaryColor,
                size: 18,
              ),
              size: 32,
            ),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListRow(
                  icon: const Icon(Icons.badge_rounded, size: 20),
                  title: l10n.serverNameTitle,
                  subtitle: s?.instanceName.isNotEmpty == true
                      ? s!.instanceName
                      : (s?.serverName.isNotEmpty == true ? s!.serverName : "libzonda's Dedicated Server"),
                ),
                const ListRowSeparator(),
                ListRow(
                  icon: const Icon(Icons.people_alt_rounded, size: 20),
                  title: l10n.maxPlayersCapacity,
                  trailing: Text(
                    l10n.playersCount(s?.maxPlayers ?? 10),
                    style: AppTextStyle.subheadline.of(context, tabular: true),
                  ),
                ),
                const ListRowSeparator(),
                ListRow(
                  icon: const Icon(Icons.lan_rounded, size: 20),
                  title: l10n.listeningPort,
                  trailing: Text(
                    '${s?.port ?? 27015} UDP/TCP',
                    style: AppTextStyle.subheadline.of(context, tabular: true),
                  ),
                ),
                if (s?.pid != null && s!.pid > 0) ...[
                  const ListRowSeparator(),
                  ListRow(
                    icon: const Icon(Icons.memory_rounded, size: 20),
                    title: l10n.processPid,
                    trailing: Text(
                      '#${s.pid}',
                      style: AppTextStyle.subheadline.of(context, tabular: true),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final BadgeType statusType;
  final IconData icon;
  final bool isPulsing;
  final bool tabular;

  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.statusType,
    required this.icon,
    this.isPulsing = false,
    this.tabular = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: SurfaceLevel.card.colorOf(context),
        shape: AppShape.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconWell(
                icon: Icon(
                  icon,
                  size: 16,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
                size: 28,
              ),
              StatusBadge(label: label, type: statusType),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (isPulsing) ...[
                PulsingDot(
                  color: isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight,
                  size: 7,
                  isPulsing: true,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  value,
                  style: AppTextStyle.headline.of(
                    context,
                    emphasized: true,
                    tabular: tabular,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
