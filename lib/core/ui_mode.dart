import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The UI mode preference of the application.
///
/// In [UiMode.simple] (default), the app hides all Nostr cryptography,
/// relays, pubkeys, hold invoices, and low-level protocol mechanics,
/// presenting a clean 5-destination navigation flow.
///
/// In [UiMode.advanced], the app exposes full sovereign control: order book,
/// custom relays, node switcher, Nostr key management, and diagnostics.
enum UiMode {
  simple,
  advanced,
}

/// SharedPreferences key for persisting the user's UI mode preference.
const String kUiModeKey = 'ui_mode_preference';

/// Global provider for the active UI mode.
final uiModeProvider = StateNotifierProvider<UiModeNotifier, UiMode>(
  (ref) => UiModeNotifier(),
);

/// Manages and persists the user's UI mode selection.
class UiModeNotifier extends StateNotifier<UiMode> {
  UiModeNotifier({SharedPreferences? prefs, UiMode? initial})
      : _prefs = prefs,
        super(initial ?? UiMode.simple) {
    if (initial == null && _prefs == null) {
      _load();
    }
  }

  SharedPreferences? _prefs;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      final saved = prefs.getString(kUiModeKey);
      if (saved != null) {
        state = UiMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => UiMode.simple,
        );
      }
    } catch (_) {
      // Fail-safe: default to simple mode on storage error.
      state = UiMode.simple;
    }
  }

  /// Change the UI mode and persist the choice.
  void setMode(UiMode mode) {
    state = mode;
    _prefs?.setString(kUiModeKey, mode.name);
  }

  /// Toggle between Simple and Advanced mode.
  void toggle() {
    setMode(state == UiMode.simple ? UiMode.advanced : UiMode.simple);
  }

  /// Helper to check if currently in Simple mode.
  bool get isSimple => state == UiMode.simple;

  /// Helper to check if currently in Advanced mode.
  bool get isAdvanced => state == UiMode.advanced;
}
