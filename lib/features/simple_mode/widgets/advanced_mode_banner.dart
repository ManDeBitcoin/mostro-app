import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/core/ui_mode.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';

/// Top banner displayed in Advanced Mode to remind the user and
/// provide an immediate one-tap return to Simple Mode.
class AdvancedModeBanner extends ConsumerWidget {
  const AdvancedModeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = OrderBookPalette.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: pal.surfaceCard,
        border: Border(
          bottom: BorderSide(color: pal.navBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.tune_rounded, size: 16, color: pal.limeText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              SimpleL10n.advancedMode(context),
              style: TextStyle(
                color: pal.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: () {
              ref.read(uiModeProvider.notifier).setMode(UiMode.simple);
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    SimpleL10n.switchToSimple(context),
                    style: TextStyle(
                      color: pal.limeText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: pal.limeText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
