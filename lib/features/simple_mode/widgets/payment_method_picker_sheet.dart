import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/app_theme.dart' show AppFonts;
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/simple_mode/models/payment_method_groups.dart';
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// The heading [category] goes by in the user's language.
String paymentMethodCategoryLabel(
  AppLocalizations l10n,
  PaymentMethodCategory category,
) => switch (category) {
  PaymentMethodCategory.banks => l10n.simpleCategoryBanks,
  PaymentMethodCategory.cooperatives => l10n.simpleCategoryCooperatives,
  PaymentMethodCategory.wallets => l10n.simpleCategoryWallets,
  PaymentMethodCategory.cash => l10n.simpleCategoryCash,
  PaymentMethodCategory.crypto => l10n.simpleCategoryCrypto,
  PaymentMethodCategory.other => l10n.simpleCategoryOther,
  PaymentMethodCategory.onOffers => l10n.simpleCategoryOnOffers,
};

/// Simple Mode's payment-method picker: every method under its heading, any
/// number of them ticked, and a search box that narrows the list as it is
/// typed.
///
/// A tick applies as it is made — it is written to [ticked], which the
/// screen underneath reads too — so there is no draft to confirm or to lose:
/// the button only closes the sheet, and so does anything else that does.
///
/// It takes providers and not values because both move while it is open:
/// the community's list when its card arrives or changes, the offers with
/// the book.
///
/// Its frame is `MostroSheet`'s, drawn here because two things differ. The
/// title and the search box stay put while the list scrolls under them,
/// where `MostroSheet` scrolls its title with its content. And the sheet has
/// one height, whatever the search finds: sized to its content, it would
/// shrink and grow with every letter, and carry the box being typed in up
/// and down the screen.
class PaymentMethodPickerSheet extends ConsumerStatefulWidget {
  const PaymentMethodPickerSheet({
    super.key,
    required this.groups,
    required this.ticked,
    required this.hint,
    this.offers,
  });

  /// The methods to pick from, under their headings.
  final ProviderListenable<List<PaymentMethodGroup>> groups;

  /// What is ticked, as [paymentMethodKey]s.
  final AutoDisposeStateProvider<Set<String>> ticked;

  /// What ticking a method does, said above the list.
  final String hint;

  /// How many offers take each method, by [paymentMethodKey]. Said beside
  /// the methods that have any; null where offers are not what is picked.
  final ProviderListenable<Map<String, int>>? offers;

  @override
  ConsumerState<PaymentMethodPickerSheet> createState() =>
      _PaymentMethodPickerSheetState();
}

class _PaymentMethodPickerSheetState
    extends ConsumerState<PaymentMethodPickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  /// How much of the screen the sheet takes: the rest stays in sight above
  /// it, which says it is a sheet and is somewhere to tap to close it.
  static const _heightOfScreen = 0.92;

  /// In a window shorter than this — a phone on its side — the title and
  /// the clear link are left out, as they are whenever a keyboard is up.
  static const _crampedBelow = 500.0;

  /// Where a keyboard leaves less of the screen in sight than this, the
  /// button is left out as well: what remains is the search box and what
  /// it finds.
  static const _tinyBelow = 300.0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pal = OrderBookPalette.of(context);
    final groups = ref.watch(widget.groups);
    final ticked = ref.watch(widget.ticked);
    final offers = switch (widget.offers) {
      final counts? => ref.watch(counts),
      null => const <String, int>{},
    };
    final methods = methodsOf(groups);
    final chosen = tickedMethods(methods, ticked);
    // What the search finds; the whole list while nothing is asked for.
    final searching = isPaymentMethodSearch(_query);
    final found = searchPaymentMethods(
      groups,
      _query,
      (category) => paymentMethodCategoryLabel(l10n, category),
    );

    // Each change starts from what is ticked when the tap lands, not from
    // what was ticked when this frame was built: of two taps inside one
    // frame the second would otherwise undo the first. And from the ticks
    // on the list only ([listedTicks]) — the whole list, not what a search
    // has narrowed it to: a tick the search hides is still the user's.
    void change(Set<String> Function(Set<String> ticked) to) {
      HapticFeedback.selectionClick();
      ref
          .read(widget.ticked.notifier)
          .update((ticked) => to(listedTicks(methods, ticked)));
    }

    void toggle(String method) {
      final key = paymentMethodKey(method);
      change(
        (ticked) =>
            ticked.contains(key)
                ? ({...ticked}..remove(key))
                : {...ticked, key},
      );
    }

    Set<String> keysOf(PaymentMethodGroup group) => {
      for (final method in group.methods) paymentMethodKey(method),
    };

    // A keyboard covers the foot of the screen — on a phone's browser too,
    // where the window keeps its height and the keyboard is reported as an
    // inset. While it is up, or in a window that is short to begin with,
    // the sheet gives its room to the box and what it finds: the title and
    // the clear link go. Where a keyboard leaves no more than a strip in
    // sight the button goes too; it comes back with the keyboard gone, and
    // dragging the list sends the keyboard away. It never goes without a
    // keyboard: in a short window nothing would bring it back.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final inSight = MediaQuery.sizeOf(context).height - keyboard;
    final cramped = keyboard > 0 || inSight < _crampedBelow;
    final tiny = keyboard > 0 && inSight < _tinyBelow;

    return SafeArea(
      child: FractionallySizedBox(
        // All of the strip, where a strip is all there is.
        heightFactor: tiny ? 1 : _heightOfScreen,
        child: Padding(
          // Nothing lifts a scroll-controlled sheet off the keyboard but
          // this inset.
          padding: EdgeInsets.fromLTRB(18, 10, 18, 14 + keyboard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: pal.divider,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              SizedBox(height: cramped ? 12 : 18),
              if (!cramped) ...[
                Text(
                  l10n.paymentMethodsLabel,
                  style: TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: pal.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Above the list, not in it: it stays where it is while the
              // list scrolls, and while what it finds comes and goes.
              //
              // Keyed, and so is the list. The title comes and goes above
              // them and the foot below, and where a keyboard takes both in
              // one frame nothing else tells the framework that the box in
              // the middle is the same box: it would be built anew, without
              // the focus — and the keyboard that came for it would leave.
              KeyedSubtree(
                key: const ValueKey('search'),
                child: _SearchField(
                  controller: _search,
                  onChanged: (query) => setState(() => _query = query),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                key: const ValueKey('list'),
                child: SingleChildScrollView(
                  // Scrolling through what was found puts the keyboard
                  // away, and gives the list the room it took.
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // What a tick does is said to someone reading the
                      // list, not to someone looking for a name.
                      if (!searching)
                        Text(
                          widget.hint,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: pal.textSecondary,
                          ),
                        ),
                      if (found.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          // Announced when it comes: nothing else tells a
                          // screen reader that the list has emptied.
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              l10n.simpleMethodsNoMatch(_query.trim()),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: pal.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      for (final group in found) ...[
                        _Heading(
                          title: paymentMethodCategoryLabel(
                            l10n,
                            group.category,
                          ),
                          // How many of the heading's methods are ticked,
                          // and the control that ticks them all, are about
                          // the whole heading. A search shows part of it,
                          // so it shows neither.
                          tally:
                              searching
                                  ? null
                                  : (
                                    chosen:
                                        tickedMethods(
                                          group.methods,
                                          ticked,
                                        ).length,
                                    total: group.methods.length,
                                    onTickAll:
                                        () => change(
                                          (ticked) => {
                                            ...ticked,
                                            ...keysOf(group),
                                          },
                                        ),
                                    onTickNone:
                                        () => change(
                                          (ticked) =>
                                              ticked.difference(keysOf(group)),
                                        ),
                                  ),
                        ),
                        for (final method in group.methods)
                          Padding(
                            // Keyed, or a list that changes under the sheet
                            // — or a search that narrows it — would hand
                            // one method's tint animation to the row that
                            // took its place.
                            key: ValueKey(method),
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _MethodRow(
                              label: method,
                              isTicked: ticked.contains(
                                paymentMethodKey(method),
                              ),
                              offers: switch (offers[paymentMethodKey(
                                method,
                              )]) {
                                final count? when count > 0 => l10n
                                    .simpleOffersCount(count),
                                _ => null,
                              },
                              // The community's names are written whole.
                              // One that only an offer carries is whatever
                              // its seller typed, and is held to three
                              // lines.
                              maxLines:
                                  group.category ==
                                          PaymentMethodCategory.onOffers
                                      ? 3
                                      : null,
                              onTap: () => toggle(method),
                            ),
                          ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
              ),
              if (!tiny) ...[
                const SizedBox(height: 14),
                ModalFooter(
                  // Not the answer and not the way out: it reads as a link.
                  // Off while nothing is ticked, not gone, so the foot of
                  // the sheet is the same before and after the first tick.
                  // It unticks every method, the ones a search is hiding
                  // too.
                  links: [
                    if (!cramped)
                      ModalLink(
                        label: l10n.simpleMethodsClear,
                        onPressed:
                            chosen.isEmpty
                                ? null
                                : () => change((_) => const {}),
                      ),
                  ],
                  primary: ModalAction(
                    label: l10n.simpleMethodsDone(chosen.length),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The box that narrows the list to the names typed into it.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  static const _longestQuery = 60;

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final create = CreateOrderPalette.of(context);
    final l10n = AppLocalizations.of(context);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color),
    );

    // Named here, once, for a screen reader. The hint says on screen what
    // the box is for, but it is gone as soon as something is typed, and
    // the reader would be left with the letters.
    return Semantics(
      label: l10n.paymentMethodSearchHint,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        autocorrect: false,
        enableSuggestions: false,
        // No method's name is this long; what is typed is repeated back when
        // nothing matches it.
        inputFormatters: [LengthLimitingTextInputFormatter(_longestQuery)],
        style: TextStyle(fontSize: 15, color: pal.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: create.inset,
          border: border(pal.border),
          enabledBorder: border(pal.border),
          focusedBorder: border(pal.lime),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 12,
          ),
          // Drawn, and left out of what is read aloud: the name above is
          // the one that stays.
          hint: ExcludeSemantics(
            child: Text(
              l10n.paymentMethodSearchHint,
              style: TextStyle(fontSize: 14.5, color: pal.textFaint),
            ),
          ),
          prefixIcon: Icon(Icons.search, size: 20, color: pal.textTertiary),
          // The way back to the whole list, there once something is typed.
          suffixIcon:
              controller.text.isEmpty
                  ? null
                  : IconButton(
                    icon: Icon(Icons.close, size: 18, color: pal.textSecondary),
                    tooltip:
                        MaterialLocalizations.of(context).clearButtonTooltip,
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
        ),
      ),
    );
  }
}

/// How many of a heading's methods are ticked, and what ticks or unticks
/// them all.
typedef _Tally =
    ({int chosen, int total, VoidCallback onTickAll, VoidCallback onTickNone});

/// A heading: its name and, with a [tally], how many of its methods are
/// ticked and — where it has more than one — a control that ticks or
/// unticks them all.
class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.tally});

  final String title;

  /// Null while a search shows only part of the heading.
  final _Tally? tally;

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final count = switch (tally) {
      final tally? when tally.chosen > 0 => l10n.simpleCategoryCount(
        tally.chosen,
        tally.total,
      ),
      _ => null,
    };

    return ConstrainedBox(
      // The height the control gives the headings that have one, so the
      // ones that do not sit on the same rhythm.
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  text: title.toUpperCase(),
                  children: [
                    if (count != null)
                      TextSpan(
                        text: '  $count',
                        style: TextStyle(color: pal.limeText, letterSpacing: 0),
                      ),
                  ],
                ),
                // Capitals are how it is drawn. A screen reader takes them
                // for an acronym and spells the heading out.
                semanticsLabel: count == null ? title : '$title, $count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: pal.textSecondary,
                ),
              ),
            ),
          ),
          if (tally case final tally? when tally.total > 1)
            TextButton(
              onPressed:
                  tally.chosen == tally.total
                      ? tally.onTickNone
                      : tally.onTickAll,
              style: TextButton.styleFrom(
                foregroundColor: pal.limeText,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                // A button's text style replaces the theme's instead of
                // building on it, so the family has to be named.
                textStyle: const TextStyle(
                  fontFamily: AppFonts.ui,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              // One word on screen, where the heading beside it says the
              // rest; read aloud it has to name the heading itself.
              child: Text(
                tally.chosen == tally.total
                    ? l10n.simpleCategoryTickNone
                    : l10n.simpleCategoryTickAll,
                semanticsLabel:
                    tally.chosen == tally.total
                        ? l10n.simpleCategoryTickNoneLabel(title)
                        : l10n.simpleCategoryTickAllLabel(title),
              ),
            ),
        ],
      ),
    );
  }
}

/// One method: a checkbox and its name, the whole row tappable.
class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.label,
    required this.isTicked,
    required this.offers,
    required this.maxLines,
    required this.onTap,
  });

  final String label;
  final bool isTicked;

  /// "3 offers", or null where there is nothing to say.
  final String? offers;

  /// How many lines the name may take; null for as many as it needs.
  final int? maxLines;
  final VoidCallback onTap;

  static const _transition = Duration(milliseconds: 120);

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final create = CreateOrderPalette.of(context);

    return Semantics(
      checked: isTicked,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: _transition,
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: isTicked ? create.pickerRowSelectedBg : create.inset,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  isTicked
                      ? create.pickerRowSelectedBorder
                      : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: _transition,
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isTicked ? pal.lime : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isTicked ? pal.lime : create.pickerCheckboxBorder,
                    width: 1.5,
                  ),
                ),
                child:
                    isTicked
                        ? Icon(Icons.check, size: 13, color: pal.onLime)
                        : null,
              ),
              const SizedBox(width: 12),
              // The name wraps: a method is told from its neighbour by its
              // last words as often as by its first.
              Expanded(
                child: Text(
                  label,
                  maxLines: maxLines,
                  overflow: maxLines == null ? null : TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: isTicked ? FontWeight.w600 : FontWeight.w400,
                    color: isTicked ? pal.textPrimary : pal.textBody,
                  ),
                ),
              ),
              if (offers case final count?) ...[
                const SizedBox(width: 10),
                Text(
                  count,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: pal.limeText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
