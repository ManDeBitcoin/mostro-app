import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/ui_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UiMode and uiModeProvider', () {
    test('defaults to UiMode.simple on fresh install without prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = UiModeNotifier(prefs: prefs);

      expect(notifier.state, equals(UiMode.simple));
      expect(notifier.isSimple, isTrue);
      expect(notifier.isAdvanced, isFalse);
    });

    test('rehydrates UiMode.advanced when saved in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        kUiModeKey: 'advanced',
      });
      final prefs = await SharedPreferences.getInstance();
      final notifier = UiModeNotifier(prefs: prefs, initial: UiMode.advanced);

      expect(notifier.state, equals(UiMode.advanced));
      expect(notifier.isAdvanced, isTrue);
      expect(notifier.isSimple, isFalse);
    });

    test('setMode updates state and persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = UiModeNotifier(prefs: prefs);

      expect(notifier.state, equals(UiMode.simple));

      notifier.setMode(UiMode.advanced);
      expect(notifier.state, equals(UiMode.advanced));
      expect(prefs.getString(kUiModeKey), equals('advanced'));

      notifier.setMode(UiMode.simple);
      expect(notifier.state, equals(UiMode.simple));
      expect(prefs.getString(kUiModeKey), equals('simple'));
    });

    test('toggle switches between simple and advanced', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = UiModeNotifier(prefs: prefs);

      expect(notifier.state, equals(UiMode.simple));

      notifier.toggle();
      expect(notifier.state, equals(UiMode.advanced));
      expect(prefs.getString(kUiModeKey), equals('advanced'));

      notifier.toggle();
      expect(notifier.state, equals(UiMode.simple));
      expect(prefs.getString(kUiModeKey), equals('simple'));
    });
  });
}
