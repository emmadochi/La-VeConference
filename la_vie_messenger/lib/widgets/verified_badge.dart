import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum VerifiedType {
  /// Blue/Cyan checkmark for official or verified identity
  blue,

  /// Gold badge for premium founders or subscribers
  gold,

  /// Mint badge for verified custom LiChat PINs
  mint,
}

class VerifiedBadge extends StatelessWidget {
  final VerifiedType type;
  final double size;
  final bool showTooltip;
  final VoidCallback? onTap;

  const VerifiedBadge({
    super.key,
    this.type = VerifiedType.blue,
    this.size = 16.0,
    this.showTooltip = true,
    this.onTap,
  });

  Color get _badgeColor {
    switch (type) {
      case VerifiedType.gold:
        return const Color(0xFFFFB300); // Amber / Gold
      case VerifiedType.mint:
        return AppTheme.mint;
      case VerifiedType.blue:
        return const Color(0xFF00A3FF); // Telegram / Twitter style Blue
    }
  }

  String get _tooltipText {
    switch (type) {
      case VerifiedType.gold:
        return 'LiChat Gold Subscriber';
      case VerifiedType.mint:
        return 'Verified Custom LiChat PIN';
      case VerifiedType.blue:
        return 'Verified LiChat Member';
    }
  }

  IconData get _badgeIcon {
    switch (type) {
      case VerifiedType.gold:
      case VerifiedType.mint:
      case VerifiedType.blue:
        return Icons.verified_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget badge = GestureDetector(
      onTap: onTap ??
          () {
            showModalBottomSheet(
              context: context,
              backgroundColor: AppTheme.surfaceColor(context),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              builder: (ctx) {
                final textPrim = AppTheme.text(ctx);
                final textSec = AppTheme.textSec(ctx);
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 38,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: AppTheme.borderColor(ctx),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _badgeColor.withValues(alpha: 0.15),
                          ),
                          child: Icon(_badgeIcon, color: _badgeColor, size: 40),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _tooltipText,
                          style: TextStyle(
                            color: textPrim,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This badge confirms that this account and its unique LiChat handle have been verified on the network.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textSec, fontSize: 13.5, height: 1.4),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _badgeColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Icon(
          _badgeIcon,
          size: size,
          color: _badgeColor,
        ),
      ),
    );

    if (showTooltip) {
      return Tooltip(
        message: _tooltipText,
        child: badge,
      );
    }

    return badge;
  }
}

