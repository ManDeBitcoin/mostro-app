import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/models/payment_details_rules.dart';
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/features/simple_mode/providers/payment_details_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// How long a field stays quiet before what it holds is kept.
const Duration kPaymentDetailsSaveDelay = Duration(milliseconds: 600);

/// The most a field takes, as `MAX_DETAILS_CHARS` in
/// `rust/src/mostro/payment_details.rs`.
const int kPaymentDetailsMaxLength = 1000;

/// The seller's payment details, a field to a payment method.
///
/// Each field opens with what the device keeps for its method and keeps
/// what is typed into it — a moment after the last keystroke, when the
/// field loses focus, and when it goes away. So a seller writes an account
/// once, on whichever screen first asks, and finds it on the next.
///
/// The fields are the device's copy, not a draft of one order: nothing here
/// publishes or sends. [onChanged] reports what they hold so the screen
/// around them can show or send it.
class PaymentDetailsEditor extends ConsumerStatefulWidget {
  const PaymentDetailsEditor({
    super.key,
    required this.methods,
    required this.onChanged,
    this.selectable = false,
    this.enabled = true,
    this.fieldColor,
  });

  /// The methods to ask for, in the order shown.
  final List<String> methods;

  /// What the fields hold, in the order of [methods], after every change.
  final ValueChanged<List<PaymentDetailsEntry>> onChanged;

  /// Whether each method carries a tick, for a seller choosing what goes
  /// into one message. Without it every entry reports as included.
  final bool selectable;

  /// Off while the screen around is sending what the fields hold.
  final bool enabled;

  /// The fill of a field; the card colour unless the editor sits on a card.
  final Color? fieldColor;

  @override
  ConsumerState<PaymentDetailsEditor> createState() =>
      _PaymentDetailsEditorState();
}

class _Field {
  _Field(this.method);

  /// The method's name as last listed.
  String method;
  final controller = TextEditingController();
  final focus = FocusNode();

  /// The user typed here: what the device keeps no longer overwrites it.
  bool touched = false;
  bool included = true;
  Timer? saving;

  void dispose() {
    saving?.cancel();
    controller.dispose();
    focus.dispose();
  }
}

class _PaymentDetailsEditorState extends ConsumerState<PaymentDetailsEditor> {
  /// By [paymentMethodKey]: a method that comes back spelled differently is
  /// the same field.
  final _fields = <String, _Field>{};

  /// Read once: `ref` is gone by the time [dispose] keeps what is pending.
  late final PaymentDetailsGateway _gateway;

  /// Bumped when the fields start over, so an answer asked for before does
  /// not fill them.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _gateway = ref.read(paymentDetailsGatewayProvider);
    _syncFields();
  }

  @override
  void didUpdateWidget(PaymentDetailsEditor old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.methods, widget.methods)) {
      _syncFields();
      _reportAfterFrame();
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      _keepNow(field);
      field.dispose();
    }
    super.dispose();
  }

  /// One field per listed method: new ones are made and filled from what
  /// the device keeps, the ones no longer listed are kept and let go.
  void _syncFields() {
    final listed = {
      for (final method in _listed()) paymentMethodKey(method): method,
    };
    for (final key in _fields.keys.toList()) {
      if (listed.containsKey(key)) continue;
      final gone = _fields.remove(key)!;
      _keepNow(gone);
      gone.dispose();
    }
    final added = <String>[];
    listed.forEach((key, method) {
      final field = _fields[key];
      if (field != null) {
        field.method = method;
        return;
      }
      final made = _Field(method);
      made.focus.addListener(() {
        if (!made.focus.hasFocus) _keepNow(made);
      });
      _fields[key] = made;
      added.add(method);
    });
    if (added.isNotEmpty) unawaited(_fill(added));
  }

  /// Fills the fields of [methods] with what the device keeps for them.
  Future<void> _fill(List<String> methods) async {
    final generation = _generation;
    final List<({String method, String details})> kept;
    try {
      kept = [
        for (final entry in await _gateway.detailsFor(methods))
          (method: entry.method, details: entry.details),
      ];
    } catch (e) {
      // Nothing read is nothing kept: the fields stay empty and usable.
      debugPrint('[payment-details] could not read the kept details: $e');
      return;
    }
    if (!mounted || generation != _generation) return;
    for (final entry in kept) {
      final field = _fields[paymentMethodKey(entry.method)];
      if (field == null || field.touched || entry.details.isEmpty) continue;
      field.controller.text = entry.details;
    }
    setState(() {});
    widget.onChanged(_entries());
  }

  /// The previous identity's details leave the screen with it: nothing
  /// pending is kept — it would land in the next identity's store — and
  /// the fields are read again, from a store that now holds none.
  void _startOver() {
    _generation++;
    for (final field in _fields.values) {
      field.saving?.cancel();
      field.saving = null;
      field.touched = false;
      field.included = true;
      field.controller.clear();
    }
    setState(() {});
    widget.onChanged(_entries());
    unawaited(_fill([for (final field in _fields.values) field.method]));
  }

  void _onTyped(_Field field) {
    field.touched = true;
    field.saving?.cancel();
    field.saving = Timer(kPaymentDetailsSaveDelay, () => _keepNow(field));
    widget.onChanged(_entries());
  }

  /// Keeps what [field] holds, if a keystroke is still waiting to be kept.
  void _keepNow(_Field field) {
    final pending = field.saving;
    if (pending == null) return;
    pending.cancel();
    field.saving = null;
    // Never the text in a log: only that the save failed, and why.
    unawaited(
      _gateway
          .save(field.method, field.controller.text)
          .catchError(
            (Object e) =>
                debugPrint('[payment-details] could not keep the details: $e'),
          ),
    );
  }

  /// [PaymentDetailsEditor.methods] without repeats: a method listed twice
  /// under two spellings is one field.
  List<String> _listed() {
    final seen = <String>{};
    return [
      for (final method in widget.methods)
        if (method.trim().isNotEmpty && seen.add(paymentMethodKey(method)))
          method,
    ];
  }

  List<PaymentDetailsEntry> _entries() => [
    for (final method in _listed())
      if (_fields[paymentMethodKey(method)] case final field?)
        PaymentDetailsEntry(
          method: method,
          details: field.controller.text.trim(),
          included: !widget.selectable || field.included,
        ),
  ];

  void _reportAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(_entries());
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(paymentDetailsOwnerProvider, (_, _) => _startOver());
    final pal = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, method) in _listed().indexed)
          if (_fields[paymentMethodKey(method)] case final field?) ...[
            if (index > 0) const SizedBox(height: 12),
            Row(
              children: [
                if (widget.selectable)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Checkbox(
                        key: ValueKey(
                          'payment-details-tick-${paymentMethodKey(method)}',
                        ),
                        value: field.included,
                        activeColor: pal.limeText,
                        checkColor: Colors.black,
                        semanticLabel: l10n.simplePayDetailsInclude(method),
                        onChanged:
                            widget.enabled
                                ? (ticked) {
                                  setState(
                                    () => field.included = ticked ?? false,
                                  );
                                  widget.onChanged(_entries());
                                }
                                : null,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    method,
                    style: TextStyle(
                      color: pal.textTitle,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: widget.fieldColor ?? pal.surfaceCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: pal.navBorder),
              ),
              child: Semantics(
                label: method,
                child: TextField(
                  key: ValueKey(
                    'payment-details-field-${paymentMethodKey(method)}',
                  ),
                  controller: field.controller,
                  focusNode: field.focus,
                  enabled:
                      widget.enabled && (!widget.selectable || field.included),
                  onChanged: (_) => _onTyped(field),
                  // A formatter, not `maxLength`: that one draws a counter
                  // row under the text, and a limit meant for a stray paste
                  // is not something to count towards.
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(kPaymentDetailsMaxLength),
                  ],
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: pal.textTitle, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: SimpleL10n.paymentDetailsHint(context),
                    hintStyle: TextStyle(color: pal.textTertiary, fontSize: 13),
                    // The box around is the field's frame: without these
                    // the theme draws its own fill and underline inside it.
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    isDense: true,
                  ),
                ),
              ),
            ),
          ],
      ],
    );
  }
}
