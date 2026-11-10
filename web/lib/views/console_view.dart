import 'dart:async';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import '../utils/file_picker_helper.dart';
import '../widgets/app_dialog.dart';
import '../widgets/current_instance_badge.dart';
import '../widgets/page_header.dart';
import '../widgets/squircle_button.dart';
import '../widgets/status_badge.dart';

class ConsoleView extends StatefulWidget {
  const ConsoleView({super.key});

  @override
  State<ConsoleView> createState() => _ConsoleViewState();
}

class _ConsoleViewState extends State<ConsoleView> {
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _filterController = TextEditingController();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _isConnected = false;
  bool _autoScroll = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
    _filterController.addListener(() {
      setState(() {
        _filter = _filterController.text.trim().toLowerCase();
      });
    });
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 60),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(max);
      }
    });
  }

  void _connectWebSocket() {
    try {
      _channel = ApiService.instance.connectLogsChannel();
      _sub = _channel?.stream.listen(
        (data) {
          if (!mounted) return;
          final str = data.toString();
          final lines = str.split('\n');
          setState(() {
            _isConnected = true;
            for (var l in lines) {
              if (l.trim().isNotEmpty) {
                if (l.contains('[Manager] Starting Core Keeper Server') ||
                    l.contains('[Manager] SteamCMD Update process initiated')) {
                  _logs.clear();
                }
                _logs.add(l);
              }
            }
            if (_logs.length > 3000) {
              _logs.removeRange(0, _logs.length - 3000);
            }
          });
          _scrollToBottom();
        },
        onError: (_) {
          if (mounted) setState(() => _isConnected = false);
          _scheduleReconnect();
        },
        onDone: () {
          if (mounted) setState(() => _isConnected = false);
          _scheduleReconnect();
        },
      );
      if (mounted) setState(() => _isConnected = true);
    } catch (_) {
      if (mounted) setState(() => _isConnected = false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_isConnected) {
        _connectWebSocket();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _channel?.sink.close();
    _scrollController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _copyAllLogs() async {
    final l10n = context.l10n;
    final text = _logs.join('\n');
    if (text.isEmpty) return;
    await copyTextToClipboard(text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.logsCopied),
          backgroundColor: SurfaceLevel.block.colorOf(context),
          behavior: SnackBarBehavior.floating,
          shape: AppShape.sm,
        ),
      );
    }
  }

  void _exportLogs() {
    final l10n = context.l10n;
    final text = _logs.join('\n');
    if (text.isEmpty) return;
    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    final timestamp = '${now.year}${pad(now.month)}${pad(now.day)}_${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
    final filename = 'corekeeper_logs_$timestamp.txt';
    downloadTextFile(text, filename);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.logsExported),
          backgroundColor: SurfaceLevel.block.colorOf(context),
          behavior: SnackBarBehavior.floating,
          shape: AppShape.sm,
        ),
      );
    }
  }

  Future<void> _clearLogs() async {
    final l10n = context.l10n;
    final confirm = await showAppDialog(
      context: context,
      title: l10n.clearLogs,
      content: l10n.logsCleared,
      confirmText: l10n.clearLogs,
      isDestructive: true,
    );

    if (confirm == true) {
      setState(() {
        _logs.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = context.l10n;

    if (_autoScroll) {
      _scrollToBottom(animate: false);
    }

    final filteredLogs = _filter.isEmpty
        ? _logs
        : _logs.where((l) => l.toLowerCase().contains(_filter)).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;
        final isMobile = constraints.maxWidth < 500;
        final isButtonCompact = constraints.maxWidth < 1050;
        final horizontalPadding = isMobile ? 12.0 : (isNarrow ? 16.0 : 24.0);
        final verticalPadding = isNarrow ? 16.0 : 24.0;

        // Title and Subtitle Block
        final titleBlock = PageHeader(
          title: l10n.consoleTitle,
          subtitle: l10n.consoleSubtitle,
          titleTrailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusBadge(
                label: _isConnected ? 'WS OK' : 'WS Reconnecting',
                type: _isConnected ? BadgeType.success : BadgeType.warning,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.linesCount(filteredLogs.length),
                style: AppTextStyle.caption1.of(
                  context,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  tabular: true,
                ),
              ),
            ],
          ),
        );

        // Search Input
        final searchInput = TextField(
          controller: _filterController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, size: 16),
            hintText: l10n.searchLogsHint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            suffixIcon: _filter.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 14),
                    onPressed: () => _filterController.clear(),
                  )
                : null,
          ),
        );

        // Action Buttons with responsive icon/text modes
        final lockBtn = SquircleButton(
          variant: _autoScroll ? ButtonVariant.primary : ButtonVariant.secondary,
          icon: Icon(_autoScroll ? Icons.lock_rounded : Icons.lock_open_rounded, size: 15),
          onPressed: () => setState(() => _autoScroll = !_autoScroll),
          tooltip: _autoScroll ? l10n.lockScroll : l10n.pauseScroll,
          padding: isButtonCompact ? const EdgeInsets.all(10) : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: isButtonCompact ? null : Text(_autoScroll ? l10n.lockScroll : l10n.pauseScroll),
        );

        final copyBtn = SquircleButton(
          variant: ButtonVariant.secondary,
          icon: const Icon(Icons.copy_rounded, size: 15),
          onPressed: _copyAllLogs,
          tooltip: l10n.copyLogs,
          padding: isButtonCompact ? const EdgeInsets.all(10) : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: isButtonCompact ? null : Text(l10n.copyLogs),
        );

        final exportBtn = SquircleButton(
          variant: ButtonVariant.secondary,
          icon: const Icon(Icons.download_rounded, size: 15),
          onPressed: _exportLogs,
          tooltip: l10n.exportLogs,
          padding: isButtonCompact ? const EdgeInsets.all(10) : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: isButtonCompact ? null : Text(l10n.exportLogs),
        );

        final clearBtn = SquircleButton(
          variant: ButtonVariant.ghost,
          icon: const Icon(Icons.delete_outline_rounded, size: 15),
          onPressed: _clearLogs,
          tooltip: l10n.clearLogs,
          padding: isButtonCompact ? const EdgeInsets.all(10) : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: isButtonCompact ? null : Text(l10n.clearLogs),
        );

        // Responsive Header
        final Widget headerWidget = !isNarrow
            ? Row(
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: 16),
                  CurrentInstanceBadge(isCompact: isButtonCompact),
                  const SizedBox(width: 10),
                  SizedBox(width: isButtonCompact ? 160 : 200, child: searchInput),
                  const SizedBox(width: 8),
                  lockBtn,
                  const SizedBox(width: 6),
                  copyBtn,
                  const SizedBox(width: 6),
                  exportBtn,
                  const SizedBox(width: 6),
                  clearBtn,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: titleBlock),
                      const SizedBox(width: 8),
                      CurrentInstanceBadge(isCompact: isButtonCompact),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isMobile) ...[
                    searchInput,
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        lockBtn,
                        const SizedBox(width: 6),
                        copyBtn,
                        const SizedBox(width: 6),
                        exportBtn,
                        const SizedBox(width: 6),
                        clearBtn,
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(child: searchInput),
                        const SizedBox(width: 8),
                        lockBtn,
                        const SizedBox(width: 6),
                        copyBtn,
                        const SizedBox(width: 6),
                        exportBtn,
                        const SizedBox(width: 6),
                        clearBtn,
                      ],
                    ),
                  ],
                ],
              );

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              headerWidget,
              const SizedBox(height: 14),

              // Terminal Console Window
              Expanded(
                child: Container(
                  decoration: ShapeDecoration(
                    color: SurfaceLevel.card.colorOf(context),
                    shape: AppShape.md,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: AppRadius.brSm,
                    child: Container(
                      color: SurfaceLevel.block.colorOf(context),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: filteredLogs.length,
                        itemBuilder: (context, index) {
                          final line = filteredLogs[index];
                          return _buildLogLine(line, isDark);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogLine(String line, bool isDark) {
    Color textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    if (line.contains('[Server Err]') || line.contains('Error') || line.contains('failed')) {
      textColor = isDark ? AppColors.stateErrorDark : AppColors.stateErrorLight;
    } else if (line.contains('[SteamCMD]') || line.contains('Warning')) {
      textColor = isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight;
    } else if (line.contains('[Manager] >> Detected SDR Game ID:')) {
      textColor = isDark ? AppColors.primaryDark : AppColors.primaryLight;
    } else if (line.contains('[Server]')) {
      textColor = isDark ? const Color(0xFFC4C6CF) : const Color(0xFF2C3038);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText(
        line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          fontWeight: isDark ? FontWeight.w500 : FontWeight.w600,
          height: 1.4,
          color: textColor,
        ),
      ),
    );
  }
}
