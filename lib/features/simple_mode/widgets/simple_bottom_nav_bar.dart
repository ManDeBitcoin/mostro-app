import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/providers/simple_nav_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show orderBookNotificationCountProvider;

const double _barHeight = 76;

/// Bottom navigation bar for Simple Mode.
/// Provides 5 clean destinations:
/// 1. Comprar (Buy)
/// 2. Vender (Sell)
/// 3. Mis operaciones (Trades)
/// 4. Perfil (Profile)
/// 5. Ayuda (Help)
class SimpleBottomNavBar extends ConsumerWidget {
  const SimpleBottomNavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hide bottom nav on desktop if persistent sidebar is used
    if (MediaQuery.sizeOf(context).width >= AppBreakpoints.desktop) {
      return const SizedBox.shrink();
    }

    final currentIndex = ref.watch(simpleNavIndexProvider);
    final palette = OrderBookPalette.of(context);
    final tradesCount = ref.watch(orderBookNotificationCountProvider);

    final destinations = [
      (
        icon: Icons.shopping_bag_outlined,
        activeIcon: Icons.shopping_bag,
        label: SimpleL10n.navBuy(context),
        badge: 0,
      ),
      (
        icon: Icons.sell_outlined,
        activeIcon: Icons.sell,
        label: SimpleL10n.navSell(context),
        badge: 0,
      ),
      (
        icon: Icons.receipt_long_outlined,
        activeIcon: Icons.receipt_long,
        label: SimpleL10n.navTrades(context),
        badge: tradesCount,
      ),
      (
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: SimpleL10n.navProfile(context),
        badge: 0,
      ),
      (
        icon: Icons.help_outline,
        activeIcon: Icons.help,
        label: SimpleL10n.navHelp(context),
        badge: 0,
      ),
    ];

    void select(int index) {
      ref.read(simpleNavIndexProvider.notifier).state = index;
    }

    return Material(
      color: palette.surfaceNav,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.navBorder)),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          child: SizedBox(
            height: _barHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  for (final (index, destination) in destinations.indexed)
                    Expanded(
                      child: _SimpleNavItem(
                        icon: index == currentIndex
                            ? destination.activeIcon
                            : destination.icon,
                        label: destination.label,
                        badgeCount: destination.badge,
                        isActive: index == currentIndex,
                        palette: palette,
                        onTap: () => select(index),
                      ),
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

class _SimpleNavItem extends StatelessWidget {
  const _SimpleNavItem({
    required this.icon,
    required this.label,
    required this.badgeCount,
    required this.isActive,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int badgeCount;
  final bool isActive;
  final OrderBookPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? palette.limeText : palette.textTertiary;

    return Semantics(
      selected: isActive,
      label: label,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 22, color: color),
                if (badgeCount > 0)
                  Positioned(
                    top: -3,
                    right: -7,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: palette.limeText,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
