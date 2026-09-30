import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/services/identity_service.dart';
import 'package:mostro/src/rust/api/identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test(
    'loadExisting routes to importFromNsec seam when omitting load callback',
    () async {
      String? passedNsec;
      final appliedPrivacy = <bool>[];
      final stored = StoredIdentity(
        words: [testNsec],
        tradeKeyIndex: 0,
        privacyMode: true,
        createdAtMillis: 1000,
      );

      final result = await IdentityService.loadExisting(
        stored,
        importNsec: ({required String nsec}) async {
          passedNsec = nsec;
          return const IdentityInfo(
            publicKey: 'mock_pubkey',
            privacyMode: true,
            tradeKeyIndex: 0,
            createdAt: 1000,
          );
        },
        applyPrivacyMode: (p) async => appliedPrivacy.add(p),
      );

      expect(result, [testNsec]);
      expect(passedNsec, testNsec);
      expect(appliedPrivacy, [true]);
    },
  );

  test('validateNsec delegates to validate seam', () async {
    String? passedNsec;
    await IdentityService.validateNsec(
      testNsec,
      validate: ({required String nsec}) async {
        passedNsec = nsec;
      },
    );
    expect(passedNsec, testNsec);
  });

  test(
    'importNsecAndStore validates nsec before deleting identity or importing',
    () async {
      var deleted = false;
      var imported = false;

      await expectLater(
        () => IdentityService.importNsecAndStore(
          'nsec1invalid',
          validateNsec: ({required String nsec}) async =>
              throw StateError('InvalidKey'),
          deleteIdentity: () async => deleted = true,
          importNsec: ({required String nsec}) async {
            imported = true;
            return const IdentityInfo(
              publicKey: 'pubkey',
              privacyMode: false,
              tradeKeyIndex: 0,
              createdAt: 1000,
            );
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(deleted, isFalse);
      expect(imported, isFalse);
    },
  );
}
