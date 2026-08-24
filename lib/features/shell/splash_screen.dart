// lib/features/shell/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/app_strings.dart';
import '../../core/i18n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';

class SplashScreen extends StatelessWidget {
  final String? error;
  final VoidCallback? onRetry;
  const SplashScreen({super.key, this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Scaffold(
      backgroundColor: AppColors.bg(d),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Mark(),
              const SizedBox(height: 22),
              Text(S.app,
                style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800,
                  letterSpacing: -0.9, color: AppColors.text(d))),
              const SizedBox(height: 6),
              Text(tr(S.slogan),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600,
                  color: AppColors.text3(d))),
              const SizedBox(height: 34),
              if (error == null)
                const SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.6))
              else ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.soft(AppColors.red, d),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line(AppColors.red, d)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(PhosphorIconsFill.warningCircle,
                        size: 19, color: AppColors.red),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(error!,
                          style: TextStyle(
                            fontSize: 12.5, height: 1.45,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSoft(AppColors.red, d))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: 220,
                  child: SqAction(tr(S.retry),
                    icon: PhosphorIconsBold.arrowClockwise,
                    onTap: onRetry)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) => SqFloat(
    distance: 6,
    child: Container(
      width: 92, height: 92,
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          const BoxShadow(
            color: AppColors.inkLip, offset: Offset(0, 6), blurRadius: 0),
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 30, offset: const Offset(0, 16)),
        ],
      ),
      alignment: Alignment.center,
      child: const SqNum('SQ',
        size: 32, color: Colors.white, letterSpacing: -1),
    ),
  );
}
