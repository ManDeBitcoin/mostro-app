import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/account/restore/restore_run.dart';
import 'package:mostro/features/account/restore/restore_sheet.dart';
import 'package:mostro/src/rust/api/reputation.dart' as reputation_api;

/// Whether there is an account on the node to restore, asked by Account →
/// Refresh and by a node switch alike (FR-058b): not in privacy mode, which
/// has none, nor when that cannot be told. What came before (the refresh,
/// the switch) already happened, and a failed check must not turn it into a
/// failure.
Future<bool> shouldRestoreAccount({
  Future<bool> Function() privacyMode = reputation_api.getPrivacyMode,
}) async {
  try {
    return !await privacyMode();
  } catch (e) {
    debugPrint('[restore] privacy mode unavailable: $e');
    return false;
  }
}

/// Restores the account on the node just switched to (#813), in the same
/// sheet as Account → Refresh, resolving once the user closes it, unless
/// [shouldRestoreAccount] says there is nothing to restore. The switch
/// stands whatever the restore does; a failed one offers its retry in the
/// sheet.
Future<void> restoreAfterNodeSwitch(
  BuildContext context, {
  Future<bool> Function() privacyMode = reputation_api.getPrivacyMode,
  RestoreRun Function() run = RestoreRun.core,
}) async {
  if (!await shouldRestoreAccount(privacyMode: privacyMode)) return;
  if (!context.mounted) return;
  await showRestoreSheet(context, run: run());
}

/// [restoreAfterNodeSwitch], for the screens that switch node through a
/// provider; a test replaces it.
final restoreAfterNodeSwitchProvider =
    Provider<Future<void> Function(BuildContext)>(
      (ref) => restoreAfterNodeSwitch,
    );
