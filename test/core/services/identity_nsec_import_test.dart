import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/services/identity_service.dart';

void main() {
  const testNsec =
      'nsec1vl029mgpspedva04g90vltkh6fvh240eqtv9xx0q2knsq6egvdtq9fv0wm';

  test(
    'loadExisting delegates to load callback when storing an nsec',
    () async {
      final loaded = <StoredIdentity>[];
      final appliedPrivacy = <bool>[];
      final stored = StoredIdentity(
        words: [testNsec],
        tradeKeyIndex: 0,
        privacyMode: false,
        createdAtMillis: 1000,
      );

      final result = await IdentityService.loadExisting(
        stored,
        load: (s) async => loaded.add(s),
        applyPrivacyMode: (p) async => appliedPrivacy.add(p),
      );

      expect(result, [testNsec]);
      expect(loaded, [stored]);
      expect(appliedPrivacy, [false]);
    },
  );
}
