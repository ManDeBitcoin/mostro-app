import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/shared/widgets/notification_bell.dart';

/// Top bar for Simple Mode: the badge of the community the app serves and
/// the notification bell.
class SimpleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SimpleAppBar({super.key});

  static const double _target = 48;
  static const double _glyphInset = (_target - 22) / 2;
  static const double _sideInset = 18;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final top = math.max(44.0, MediaQuery.paddingOf(context).top + 12);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _sideInset - _glyphInset,
        top - _glyphInset,
        _sideInset - _glyphInset,
        math.max(0, 12 - _glyphInset),
      ),
      child: SizedBox(
        height: _target,
        child: Row(
          children: [
            // Community badge. Not a control: the app serves one community.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: pal.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: pal.limeBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, size: 16, color: pal.limeText),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      defaultMostroName,
                      style: TextStyle(
                        color: pal.textTitle,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Notification bell
            const NotificationBell(),
          ],
        ),
      ),
    );
  }
}
