import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import '../widgets/common_card.dart';
import '../widgets/github_icon.dart';
import '../widgets/icon_well.dart';
import '../widgets/page_header.dart';
import '../widgets/squircle_button.dart';
import '../widgets/status_badge.dart';
import '../utils/app_version.dart';

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  static const String repoUrl = 'https://github.com/libzonda/core-keeper-dedicated-server';
  static const String authorUrl = 'https://github.com/libzonda';

  Future<void> _launch(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = context.l10n;
    final primaryColor = isDark ? AppColors.primaryDark : AppColors.primaryLight;
    final hairline = isDark ? AppColors.dividerHairlineDark : AppColors.dividerHairlineLight;

    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 16 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          PageHeader(
            title: l10n.aboutTitle,
            subtitle: l10n.aboutSubtitle,
            actionsBuilder: (context, isCompact) => [
              SquircleButton(
                variant: ButtonVariant.primary,
                icon: const GithubIcon(size: 16, color: Colors.white),
                onPressed: () => _launch(repoUrl),
                tooltip: l10n.visitGithub,
                child: isCompact ? null : Text(l10n.visitGithub),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Main Hero Banner Card
          CommonCard(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => IconWell(
                      icon: Icon(
                        Icons.lens_blur_rounded,
                        color: primaryColor,
                        size: 36,
                      ),
                      size: 64,
                      backgroundColor: SurfaceLevel.inset.colorOf(context),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Core Keeper Dedicated Server Manager',
                              style: AppTextStyle.title2.of(
                                context,
                                emphasized: true,
                                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          ValueListenableBuilder<String>(
                            valueListenable: AppVersion.notifier,
                            builder: (_, ver, __) => StatusBadge(
                              label: ver,
                              type: BadgeType.success,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const StatusBadge(
                            label: 'AGPL-3.0',
                            type: BadgeType.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.aboutAppDesc,
                        style: AppTextStyle.subheadline.of(
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

          // Project Information & Author Card
          CommonCard(
            title: l10n.aboutMetadataTitle,
            leading: Icon(Icons.info_outline_rounded, size: 20, color: primaryColor),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                // Author row
                _InfoTile(
                  icon: Icons.person_rounded,
                  title: l10n.aboutAuthor,
                  value: 'libzonda',
                  trailingAction: SquircleButton(
                    variant: ButtonVariant.secondary,
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    onPressed: () => _launch(authorUrl),
                    child: Text(l10n.visitAuthor),
                  ),
                ),
                Divider(height: 1, thickness: 1, color: hairline, indent: 56),

                // Repository row
                _InfoTile(
                  customIcon: GithubIcon(
                    size: 20,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                  title: l10n.aboutRepo,
                  value: 'libzonda/core-keeper-dedicated-server',
                  trailingAction: SquircleButton(
                    variant: ButtonVariant.secondary,
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    onPressed: () => _launch(repoUrl),
                    child: const Text('GitHub'),
                  ),
                ),
                Divider(height: 1, thickness: 1, color: hairline, indent: 56),

                // License row
                _InfoTile(
                  icon: Icons.gavel_rounded,
                  title: l10n.aboutLicenseTitle,
                  value: 'GNU Affero General Public License v3.0 (AGPL-3.0)',
                  badge: const StatusBadge(
                    label: 'AGPL v3.0',
                    type: BadgeType.primary,
                  ),
                ),
                Divider(height: 1, thickness: 1, color: hairline, indent: 56),

                // Version row
                ValueListenableBuilder<String>(
                  valueListenable: AppVersion.notifier,
                  builder: (_, ver, __) => _InfoTile(
                    icon: Icons.tag_rounded,
                    title: l10n.aboutVersionTitle,
                    value: ver,
                    badge: const StatusBadge(
                      label: 'Latest',
                      type: BadgeType.success,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Tech Stack & Architecture Card
          CommonCard(
            title: l10n.aboutCreditsTitle,
            leading: Icon(Icons.layers_rounded, size: 20, color: primaryColor),
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _TechBadge(
                  title: 'Core Keeper Dedicated Server',
                  subtitle: 'Official Linux Server (App ID 1963720)',
                  icon: Icons.sports_esports_rounded,
                  color: const Color(0xFFE5A93C),
                ),
                _TechBadge(
                  title: 'Steamworks & SteamCMD',
                  subtitle: 'SDR Relay Network & Workshop API',
                  icon: Icons.cloud_done_rounded,
                  color: const Color(0xFF1B98F5),
                ),
                _TechBadge(
                  title: 'Go 1.23+ Daemon',
                  subtitle: 'REST API, Process Supervisor & WebSocket',
                  icon: Icons.terminal_rounded,
                  color: const Color(0xFF00ADD8),
                ),
                _TechBadge(
                  title: 'Flutter Web 3.47+',
                  subtitle: 'Continuous Superellipse & Physical Spring UI',
                  icon: Icons.flutter_dash_rounded,
                  color: const Color(0xFF02569B),
                ),
                _TechBadge(
                  title: 'Docker & Docker Compose',
                  subtitle: 'Xvfb Virtual Display & Steam Environment',
                  icon: Icons.dns_rounded,
                  color: const Color(0xFF2496ED),
                ),
              ],
            ),
          ),

          if (!kIsWeb) ...[
            const SizedBox(height: 20),
            const _DesktopServerCard(),
          ],
        ],
      ),
    );
  }
}

class _DesktopServerCard extends StatefulWidget {
  const _DesktopServerCard();

  @override
  State<_DesktopServerCard> createState() => _DesktopServerCardState();
}

class _DesktopServerCardState extends State<_DesktopServerCard> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ApiService.instance.baseUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      await ApiService.instance.setDesktopBaseUrl(text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server endpoint updated! Reconnecting...')),
        );
      }
      await ApiService.instance.fetchVersion();
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return CommonCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconWell(
                icon: const Icon(Icons.desktop_windows_rounded, size: 20),
                backgroundColor: SurfaceLevel.inset.colorOf(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Desktop Connection Settings',
                      style: AppTextStyle.headline.of(context, emphasized: true),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Configure the backend daemon address (Default: http://127.0.0.1:8080)',
                      style: AppTextStyle.caption1.of(
                        context,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.link_rounded, size: 18),
                    hintText: 'http://127.0.0.1:8080',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SquircleButton(
                variant: ButtonVariant.primary,
                icon: const Icon(Icons.save_rounded, size: 16),
                onPressed: _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData? icon;
  final Widget? customIcon;
  final String title;
  final String value;
  final Widget? trailingAction;
  final Widget? badge;

  const _InfoTile({
    this.icon,
    this.customIcon,
    required this.title,
    required this.value,
    this.trailingAction,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: ShapeDecoration(
              color: context.raisedSurfaceLevel.colorOf(context),
              shape: AppShape.sm,
            ),
            child: Center(
              child: customIcon ??
                  Icon(
                    icon,
                    size: 18,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.caption1.of(
                    context,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyle.subheadline.of(
                    context,
                    emphasized: true,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                ),
              ],
            ),
          ),
          if (badge != null) ...[
            badge!,
            const SizedBox(width: 8),
          ],
          if (trailingAction != null) trailingAction!,
        ],
      ),
    );
  }
}

class _TechBadge extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _TechBadge({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(context),
        shape: AppShape.md,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: ShapeDecoration(
              color: color.withValues(alpha: 0.15),
              shape: AppShape.sm,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyle.caption1.of(
                    context,
                    emphasized: true,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: AppTextStyle.caption2.of(
                    context,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
