import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The 5 main navigation destinations in Simple Mode.
enum SimpleNavDestination {
  buy,
  sell,
  trades,
  profile,
  help,
}

/// Active tab index in Simple Mode (0 = buy, 1 = sell, 2 = trades, 3 = profile, 4 = help).
final simpleNavIndexProvider = StateProvider<int>((ref) => 0);
