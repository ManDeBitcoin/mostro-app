import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/simple_mode/models/payment_method_groups.dart';
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/features/simple_mode/widgets/payment_method_picker_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// The payment methods chosen on a Simple Mode tab, and the way into the
/// picker ([PaymentMethodPickerSheet]).
///
/// The community's list is too long to lay out on the tab itself, so the
/// tab shows only what is ticked — each method a chip that unticks it when
/// tapped — and the list opens over it, under its headings.
class PaymentMethodField extends ConsumerWidget {
  const PaymentMethodField({
    super.key,
    required this.groups,
    required this.ticked,
    required this.placeholder,
    required this.hint,
    this.offers,
  });

  /// The methods to pick from, under their headings.
  final ProviderListenable<List<PaymentMethodGroup>> groups;

  /// What is ticked, as [paymentMethodKey]s.
  final AutoDisposeStateProvider<Set<String>> ticked;

  /// What the field says while nothing is ticked.
  final String placeholder;

  /// What ticking a method does, said in the picker.
  final String hint;

  /// How many offers take each method; see [PaymentMethodPickerSheet.offers].
  final ProviderListenable<Map<String, int>>? offers;

  void _open(BuildContext context) {
    // Flutter hands focus back to the amount field when the sheet closes,
    // and its keyboard then covers what was just chosen.
    FocusManager.instance.primaryFocus?.unfocus();
    showMostroSheet<void>(
      context: context,
      builder:
          (_) => PaymentMethodPickerSheet(
            groups: groups,
            ticked: ticked,
            hint: hint,
            offers: offers,
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final methods = methodsOf(ref.watch(groups));
    final chosen = tickedMethods(methods, ref.watch(ticked));

    return Material(
      color: pal.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: chosen.isEmpty ? pal.navBorder : pal.limeBorder,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The way into the picker. A button to a screen reader as well:
          // an ink well alone is announced as plain text.
          Semantics(
            button: true,
            child: InkWell(
              onTap: () => _open(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      Icon(
                        Icons.payments_outlined,
                        size: 20,
                        color: pal.limeText,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          chosen.isEmpty
                              ? placeholder
                              : l10n.paymentMethodsChosenCount(chosen.length),
                          style: TextStyle(
                            color:
                                chosen.isEmpty
                                    ? pal.textSecondary
                                    : pal.textTitle,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        chosen.isEmpty
                            ? l10n.simpleMethodsPick
                            : l10n.simpleMethodsEdit,
                        style: TextStyle(
                          color: pal.limeText,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 22,
                        color: pal.limeText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Under the way in, not inside it: a tap that misses a chip does
          // nothing, where it used to open the picker.
          if (chosen.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final method in chosen)
                    _ChosenChip(
                      label: method,
                      // From what is ticked when the tap lands, not when
                      // this frame was built, and from the ticks on the
                      // list ([listedTicks]).
                      onRemove:
                          () => ref
                              .read(ticked.notifier)
                              .update(
                                (ticked) =>
                                    listedTicks(methods, ticked)
                                      ..remove(paymentMethodKey(method)),
                              ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A ticked method: lime tint, like everything else the user has chosen.
/// Tapping it — anywhere on it, the cross only says so — unticks the method
/// without opening the picker.
class _ChosenChip extends StatelessWidget {
  const _ChosenChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);

    return Semantics(
      button: true,
      label: AppLocalizations.of(context).removePaymentMethod(label),
      excludeSemantics: true,
      onTap: onRemove,
      child: Material(
        color: pal.bestChipFill,
        shape: StadiumBorder(side: BorderSide(color: pal.bestChipBorder)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onRemove,
          child: ConstrainedBox(
            // The whole chip takes the tap, and is tall enough to be hit:
            // a cross of its own was a target a finger missed.
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Flexible: a name wider than the field is cut short here
                  // — the picker writes it whole — instead of pushing the
                  // cross off the chip.
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: pal.limeInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.close, size: 14, color: pal.limeText),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
