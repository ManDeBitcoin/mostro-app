import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/providers/node_picture_provider.dart';
import 'package:mostro/src/rust/api/types.dart'
    show MostroNodeEntry, MostroNodePicture;

import '../../../support/provider_harness.dart';

/// Each relay round trip waits on a completer the test resolves, and is
/// counted — no Rust bridge.
class _GatedNodesNotifier extends MostroNodesNotifier {
  final List<Completer<List<MostroNodeEntry>>> fetches = [];

  /// What each picture sync reports as changed; counted.
  List<String> changedPictures = const [];
  int pictureSyncs = 0;

  /// Whether [build] starts a refresh, as the real one does.
  bool refreshOnBuild = false;

  @override
  Future<List<MostroNodeEntry>> build() async {
    if (refreshOnBuild) refreshMetadata();
    return const [];
  }

  @override
  Future<List<MostroNodeEntry>> fetchMetadata() {
    final fetch = Completer<List<MostroNodeEntry>>();
    fetches.add(fetch);
    return fetch.future;
  }

  /// When set, each picture sync waits for it.
  Completer<void>? pictureGate;

  @override
  Future<List<String>> syncPictures() async {
    pictureSyncs++;
    await pictureGate?.future;
    return changedPictures;
  }
}

void main() {
  late _GatedNodesNotifier notifier;
  late ProviderContainer container;

  /// How many times each node read its stored picture.
  late Map<String, int> pictureReads;

  ProviderContainer create() {
    notifier = _GatedNodesNotifier();
    pictureReads = {};
    return container = createContainer(
      overrides: [
        mostroNodesProvider.overrideWith(() => notifier),
        nodePictureProvider.overrideWith((ref, pubkey) async {
          pictureReads.update(pubkey, (n) => n + 1, ifAbsent: () => 1);
          return MostroNodePicture(
            url: 'https://x/$pubkey.png',
            bytes: Uint8List(0),
          );
        }),
      ],
    );
  }

  Future<void> start() async {
    await create().read(mostroNodesProvider.future);
  }

  test('a refresh during another one joins it', () async {
    // Arrange
    await start();
    final first = notifier.refreshMetadata();

    // Act
    final second = notifier.refreshMetadata();
    notifier.fetches.single.complete(const []);
    await Future.wait([first, second]);

    // Assert
    expect(notifier.fetches, hasLength(1));
  });

  test(
    'refreshMetadataAfterPending runs again after the one in flight',
    () async {
      // Arrange
      await start();
      final first = notifier.refreshMetadata();

      // Act
      final again = notifier.refreshMetadataAfterPending();
      await pumpEventQueue();
      expect(notifier.fetches, hasLength(1), reason: 'waits for the first');
      notifier.fetches.first.complete(const []);
      await first;
      await pumpEventQueue();

      // Assert
      expect(notifier.fetches, hasLength(2));
      notifier.fetches.last.complete(const []);
      await again;
    },
  );

  test('refreshMetadataAfterPending refreshes at once when idle', () async {
    await start();

    final run = notifier.refreshMetadataAfterPending();
    await pumpEventQueue();

    expect(notifier.fetches, hasLength(1));
    notifier.fetches.single.complete(const []);
    await run;
  });

  test(
    'a refresh syncs the pictures and re-reads the ones that changed',
    () async {
      // Arrange
      await start();
      notifier.changedPictures = const ['aa'];
      await container.read(nodePictureProvider('aa').future);
      await container.read(nodePictureProvider('bb').future);

      // Act
      final run = notifier.refreshMetadata();
      notifier.fetches.single.complete(const []);
      await run;
      await pumpEventQueue();
      await container.read(nodePictureProvider('aa').future);
      await container.read(nodePictureProvider('bb').future);

      // Assert
      expect(notifier.pictureSyncs, 1);
      expect(pictureReads, {'aa': 2, 'bb': 1});
    },
  );

  test(
    'a refresh reads every stored picture, so the first QR need not',
    () async {
      // Arrange
      await start();
      MostroNodeEntry node(String pubkey, String? picture) => MostroNodeEntry(
        pubkey: pubkey,
        region: null,
        isTrusted: true,
        isActive: false,
        name: null,
        picture: picture,
        about: null,
        website: null,
      );

      // Act
      final run = notifier.refreshMetadata();
      notifier.fetches.single.complete([
        node('AA', 'https://x/a.png'),
        node('bb', null),
      ]);
      await run;
      await pumpEventQueue();

      // Assert: by the lowercase key the avatar reads; none for no picture.
      expect(pictureReads, {'aa': 1});
    },
  );

  test('a failed fetch still syncs the pictures the cache names', () async {
    // Arrange
    await start();

    // Act
    final run = notifier.refreshMetadata();
    notifier.fetches.single.completeError(StateError('relays down'));
    await run;
    await pumpEventQueue();

    // Assert
    expect(notifier.pictureSyncs, 1);
  });

  test('the picture downloads hold no refresh back', () async {
    // Arrange
    await start();
    notifier.pictureGate = Completer<void>();
    final first = notifier.refreshMetadata();
    notifier.fetches.single.complete(const []);
    await first;
    await pumpEventQueue();
    expect(notifier.pictureSyncs, 1, reason: 'downloading');

    // Act
    final second = notifier.refreshMetadata();
    await pumpEventQueue();

    // Assert
    expect(notifier.fetches, hasLength(2));
    notifier.fetches.last.complete(const []);
    await second;
    notifier.pictureGate!.complete();
  });

  group('refreshNodeProfilesOnceConnected', () {
    test(
      'waits for the relays, then builds a registry not built yet',
      () async {
        // Arrange
        create();
        notifier.refreshOnBuild = true;
        final connected = Completer<void>();

        // Act
        final run = refreshNodeProfilesOnceConnected(
          container,
          connected.future,
        );
        await pumpEventQueue();
        expect(container.exists(mostroNodesProvider), isFalse);
        connected.complete();
        await run;

        // Assert: the build's own refresh, and no second one.
        expect(notifier.fetches, hasLength(1));
        notifier.fetches.single.complete(const []);
      },
    );

    test(
      'fetches again for a registry built before the relays were up',
      () async {
        // Arrange
        create();
        notifier.refreshOnBuild = true;
        await container.read(mostroNodesProvider.future);
        expect(notifier.fetches, hasLength(1), reason: 'the early fetch');

        // Act
        final run = refreshNodeProfilesOnceConnected(container, Future.value());
        await pumpEventQueue();
        notifier.fetches.first.complete(const []);
        await pumpEventQueue();

        // Assert
        expect(notifier.fetches, hasLength(2));
        notifier.fetches.last.complete(const []);
        await run;
        await pumpEventQueue();
        expect(notifier.pictureSyncs, 2);
      },
    );
  });
}
