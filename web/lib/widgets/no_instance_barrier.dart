import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'common_card.dart';
import 'icon_well.dart';
import 'squircle_button.dart';

class NoInstanceBarrierWidget extends StatelessWidget {
  final VoidCallback onGoToInstances;

  const NoInstanceBarrierWidget({
    super.key,
    required this.onGoToInstances,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.primaryDark : AppColors.primaryLight;
    final l10n = context.l10n;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: CommonCard(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                IconWell(
                  icon: Icon(Icons.dns_rounded, size: 36, color: primaryColor),
                  size: 68,
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.noInstanceBarrierTitle,
                  style: AppTextStyle.headline.of(context, emphasized: true),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.noInstanceBarrierDesc,
                  style: AppTextStyle.body.of(
                    context,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SquircleButton(
                  variant: ButtonVariant.primary,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: onGoToInstances,
                  child: Text(l10n.goToCreateInstance),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
