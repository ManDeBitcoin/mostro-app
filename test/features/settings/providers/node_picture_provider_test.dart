import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/providers/node_picture_provider.dart';
import 'package:mostro/src/rust/api/types.dart';
import 'package:mostro/src/rust/frb_generated.dart';

import '../../../support/provider_harness.dart';

/// A 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

/// A PNG signature and nothing after it: passes Rust's magic-byte check,
/// does not decode.
final _broken = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10]);

/// The node picture store as Rust keeps it, one picture per pubkey.
class _Api implements RustLibApi {
  final Map<String, MostroNodePicture> stored = {};
  final List<String> forgotten = [];

  @override
  Future<MostroNodePicture?> crateApiNodesGetMostroNodePicture({
    required String pubkey,
  }) async => stored[pubkey];

  @override
  Future<void> crateApiNodesForgetMostroNodePicture({
    required String pubkey,
  }) async {
    forgotten.add(pubkey);
    stored.remove(pubkey);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Api api;
  setUpAll(() => RustLib.initMock(api: _Delegate(() => api)));
  setUp(() => api = _Api());

  test('a stored picture that decodes is handed to the avatar', () async {
    // Arrange
    final picture = MostroNodePicture(url: 'https://x/a.png', bytes: _png);
    api.stored['aa'] = picture;

    // Act
    final read = await createContainer().read(nodePictureProvider('aa').future);

    // Assert
    expect(read, same(picture));
    expect(api.forgotten, isEmpty);
  });

  test('a stored picture that does not decode is forgotten, so the avatar '
      'loads the URL and the next sync downloads it again', () async {
    // Arrange
    api.stored['aa'] = MostroNodePicture(
      url: 'https://x/a.png',
      bytes: _broken,
    );

    // Act
    final read = await createContainer().read(nodePictureProvider('aa').future);

    // Assert
    expect(read, isNull);
    expect(api.forgotten, ['aa']);
  });
}

/// Forwards to the current test's [_Api].
class _Delegate implements RustLibApi {
  _Delegate(this._api);

  final _Api Function() _api;

  @override
  Future<MostroNodePicture?> crateApiNodesGetMostroNodePicture({
    required String pubkey,
  }) => _api().crateApiNodesGetMostroNodePicture(pubkey: pubkey);

  @override
  Future<void> crateApiNodesForgetMostroNodePicture({required String pubkey}) =>
      _api().crateApiNodesForgetMostroNodePicture(pubkey: pubkey);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
