import 'package:flutter/services.dart';

/// What a whole-amount field lets through: digits, and the two marks people
/// type as a separator — the dot and the comma.
///
/// The marks are let through on purpose. A digits-only field does not stop
/// anyone typing `10.50`: it drops the dot and keeps the cents, and `1050`
/// reads as a valid amount a hundred times the one meant. Kept on screen,
/// `10.50` is simply not a whole number: the field's own check refuses it
/// and the screen says so (`orderAmountMustBeWhole`). Whatever depends on
/// the typed amount — publishing, taking a range order — stays off until it
/// is corrected. A thousands separator (`1.000`) is refused the same way:
/// these fields do no grouping, so they cannot tell it from a decimal.
final TextInputFormatter wholeAmountInputFormatter =
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));
