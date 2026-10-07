import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';

void main() {
  test('the explainer is closed on arrival and opens only by the user', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final screen = container.listen(bondExplainerOpenProvider, (_, _) {});

    // Closed: what the screen shows then is the invoice's QR.
    expect(screen.read(), isFalse);
    container.read(bondExplainerOpenProvider.notifier).toggle();
    expect(screen.read(), isTrue);
    container.read(bondExplainerOpenProvider.notifier).toggle();
    expect(screen.read(), isFalse);
    screen.close();
  });

  test('an explainer left open is closed again at the next deposit', () async {
    // It used to come back as last left, and for a first-time user open:
    // the next deposit then opened on a text, with no QR to pay.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = container.listen(bondExplainerOpenProvider, (_, _) {});
    container.read(bondExplainerOpenProvider.notifier).toggle();
    expect(first.read(), isTrue);
    // The screen is left: nothing watches the accordion any more.
    first.close();
    await container.pump();

    final next = container.listen(bondExplainerOpenProvider, (_, _) {});
    addTearDown(next.close);
    expect(next.read(), isFalse);
  });
}
