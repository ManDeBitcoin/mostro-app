import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/simple_mode/providers/simple_nav_provider.dart';
import 'package:mostro/features/simple_mode/screens/simple_buy_screen.dart';
import 'package:mostro/features/simple_mode/screens/simple_help_screen.dart';
import 'package:mostro/features/simple_mode/screens/simple_profile_screen.dart';
import 'package:mostro/features/simple_mode/screens/simple_sell_screen.dart';
import 'package:mostro/features/simple_mode/screens/simple_trades_screen.dart';
import 'package:mostro/features/simple_mode/widgets/simple_app_bar.dart';
import 'package:mostro/features/simple_mode/widgets/simple_bottom_nav_bar.dart';

/// The root shell container for Simple Mode.
/// Hosts the SimpleAppBar, the active destination screen, and the SimpleBottomNavBar.
class SimpleShellScreen extends ConsumerWidget {
  const SimpleShellScreen({super.key});

  static const _screens = <Widget>[
    SimpleBuyScreen(),
    SimpleSellScreen(),
    SimpleTradesScreen(),
    SimpleProfileScreen(),
    SimpleHelpScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navIndex = ref.watch(simpleNavIndexProvider);
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);

    final safeIndex = navIndex.clamp(0, _screens.length - 1);

    return Theme(
      data: theme.copyWith(scaffoldBackgroundColor: pal.bg),
      child: Scaffold(
        backgroundColor: pal.bg,
        appBar: const SimpleAppBar(),
        body: IndexedStack(
          index: safeIndex,
          children: _screens,
        ),
        bottomNavigationBar: const SimpleBottomNavBar(),
      ),
    );
  }
}
