import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/ui_mode.dart';

/// Creates a [ProviderContainer] and disposes it at test tear-down, so state
/// never leaks between tests. Call from inside a `test(...)` body.
ProviderContainer createContainer({
  List<Override> overrides = const [],
  ProviderContainer? parent,
  UiMode uiMode = UiMode.advanced,
}) {
  final container = ProviderContainer(
    parent: parent,
    overrides: [
      uiModeProvider.overrideWith((ref) => UiModeNotifier(initial: uiMode)),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

