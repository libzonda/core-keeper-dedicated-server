import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/admin_item.dart';
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
import '../widgets/squircle_button.dart';
import '../widgets/status_badge.dart';

class AdminsView extends StatefulWidget {
  const AdminsView({super.key});

  @override
  State<AdminsView> createState() => _AdminsViewState();
}

class _AdminsViewState extends State<AdminsView> {
  List<AdminItem> _admins = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  Future<void> _loadAdmins() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.instance.getAdmins();
      setState(() => _admins = list);
    } catch (e) {
      _showToast('Failed to load admins: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAddAdminDialog() async {
    final l10n = context.l10n;
    final nameCtrl = TextEditingController();
    final steamIdCtrl = TextEditingController();
    int privileges = 2; // Default Full Admin

    final ok = await showAppDialog(
      context: context,
      title: l10n.addAdmin,
      content: '',
      confirmText: l10n.confirm,
      cancelText: l10n.cancel,
      customBody: StatefulBuilder(
        builder: (ctx, setDlgState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.adminName, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
            const SizedBox(height: 6),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(hintText: l10n.adminName),
            ),
            const SizedBox(height: 14),
            Text(l10n.steamId, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
            const SizedBox(height: 6),
            TextField(
              controller: steamIdCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '76561198000000000'),
            ),
            const SizedBox(height: 14),
            Text(l10n.adminRole, style: AppTextStyle.subheadline.of(ctx, emphasized: true)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: privileges,
              dropdownColor: SurfaceLevel.card.colorOf(ctx),
              items: [
                DropdownMenuItem(value: 2, child: Text(l10n.fullAdmin)),
                DropdownMenuItem(value: 1, child: Text(l10n.visitor)),
              ],
              onChanged: (v) {
                if (v != null) setDlgState(() => privileges = v);
              },
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final name = nameCtrl.text.trim();
      final steamId = steamIdCtrl.text.trim();
      if (steamId.isEmpty) {
        _showToast('Steam ID cannot be empty', isError: true);
        return;
      }
      try {
        await ApiService.instance.addAdmin(
          name: name,
          steamId: steamId,
          privileges: privileges,
        );
        _showToast('Admin added: $name ($steamId)');
        _loadAdmins();
      } catch (e) {
        _showToast('Add Failed: $e', isError: true);
      }
    }
  }

  Future<void> _deleteAdmin(AdminItem admin) async {
    final l10n = context.l10n;
    final ok = await showAppDialog(
      context: context,
      title: '${l10n.confirmDeleteAdmin} (${admin.name})',
      content: l10n.confirmDeleteAdminDesc,
      confirmText: l10n.delete,
      isDestructive: true,
    );

    if (ok == true) {
      try {
        await ApiService.instance.deleteAdmin(admin.steamId);
        _showToast('Admin removed: ${admin.name}');
        _loadAdmins();
      } catch (e) {
        _showToast('Remove Failed: $e', isError: true);
      }
    }
  }

  Future<void> _copyToClipboard(String text, String tip) async {
    await copyTextToClipboard(text);
    if (!mounted) return;
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
            title: l10n.adminsTitle,
            subtitle: l10n.adminsSubtitle,
            actionsBuilder: (context, isCompact) => [
              CurrentInstanceBadge(onInstanceChanged: _loadAdmins, isCompact: isCompact),
              SquircleButton(
                variant: ButtonVariant.primary,
                icon: const Icon(Icons.person_add_rounded, size: 16),
                onPressed: _openAddAdminDialog,
                tooltip: l10n.addAdmin,
                child: isCompact ? null : Text(l10n.addAdmin),
              ),
              SquircleButton(
                variant: ButtonVariant.secondary,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                onPressed: _loadAdmins,
                tooltip: l10n.refresh,
                child: isCompact ? null : Text(l10n.refresh),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Admin List
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (_admins.isEmpty)
            CommonCard(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Center(
                child: Column(
                  children: [
                    IconWell(
                      icon: Icon(
                        Icons.shield_outlined,
                        size: 32,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.noAdmins,
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
                itemCount: _admins.length,
                separatorBuilder: (context, index) => const ListRowSeparator(),
                itemBuilder: (context, index) {
                  final admin = _admins[index];
                  return ListRow(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    icon: Icon(
                      admin.isFullAdmin ? Icons.verified_user_rounded : Icons.person_rounded,
                      color: admin.isFullAdmin
                          ? (isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight)
                          : (isDark ? AppColors.primaryDark : AppColors.primaryLight),
                      size: 20,
                    ),
                    title: admin.name.isEmpty ? 'Unnamed' : admin.name,
                    subtitle: 'Steam64: ${admin.steamId}',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusBadge(
                          label: admin.isFullAdmin ? l10n.fullAdmin : l10n.visitor,
                          type: admin.isFullAdmin ? BadgeType.warning : BadgeType.neutral,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          tooltip: 'Copy Steam ID',
                          onPressed: () => _copyToClipboard(admin.steamId, 'Copied Steam ID'),
                        ),
                        const SizedBox(width: 4),
                        SquircleButton(
                          variant: ButtonVariant.destructive,
                          height: 32,
                          padding: isMobile ? const EdgeInsets.all(8) : const EdgeInsets.symmetric(horizontal: 12),
                          icon: const Icon(Icons.delete_outline_rounded, size: 14),
                          tooltip: l10n.remove,
                          onPressed: () => _deleteAdmin(admin),
                          child: isMobile ? null : Text(l10n.remove),
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
