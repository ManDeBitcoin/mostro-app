import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/models/create_order_rules.dart';
import 'package:mostro/features/order/providers/order_side_provider.dart';
import 'package:mostro/features/order/widgets/premium_slider_shapes.dart';
import 'package:mostro/features/order/widgets/underline_amount_field.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/widgets/pill_segmented.dart';

/// Whether Market or Fixed price mode is selected.
final isMarketPriceProvider = StateProvider<bool>((_) => true);

/// Premium slider value. Whole percent only (Mostro rounds the premium to an
/// integer). Default slider range is [-10%, +10%], but the input accepts (and
/// the slider expands to fit) values up to [-999%, +999%].
final premiumValueProvider = StateProvider<double>((_) => 0.0);

/// Default premium slider bound. The slider grows past this to fit a typed value.
const double kPremiumSliderDefault = 10.0;

/// Hard limit for a manually entered premium magnitude.
const double kPremiumMaxMagnitude = 999.0;

/// Whether the premium field holds a text that is no premium — one written
/// with decimals. The premium in [premiumValueProvider] is then **not** what
/// the user sees in the field, so the form must not publish with it: the
/// create screen reads this as "not valid yet" and says why.
final premiumInputInvalidProvider = StateProvider.autoDispose<bool>(
  (_) => false,
);

/// Fixed sats amount as plain digits (only used in Fixed price mode).
final fixedSatsProvider = StateProvider<String>((_) => '');

/// Whether the order being created is a range order (min/max fiat amount).
/// Range orders are incompatible with a fixed sats price — Mostro prices them
/// at market with a premium — so PriceSection locks the control to Market and
/// disables Fixed while this is true.
final isRangeOrderProvider = StateProvider<bool>((_) => false);

/// `+3%`, `0%`, `-3%` — the premium as the screen prints it. Zero carries no
/// sign; the value is a whole percent because the protocol stores one.
String formatPremium(double premium) {
  final whole = premium.round();
  return '${whole > 0 ? '+' : ''}$whole%';
}

/// How long the premium block and the fixed-sats field take to swap.
const _swapDuration = Duration(milliseconds: 200);

/// How long the premium block takes to change colour.
const _tintDuration = Duration(milliseconds: 180);

/// "Price" card: `Market | Fixed` control, then either the premium block
/// (market) or the sats field (fixed).
class PriceSection extends ConsumerStatefulWidget {
  const PriceSection({super.key});

  @override
  ConsumerState<PriceSection> createState() => _PriceSectionState();
}

class _PriceSectionState extends ConsumerState<PriceSection> {
  late final TextEditingController _premiumController;
  late final TextEditingController _satsController;
  bool _editingPremium = false;

  // Slider bounds captured when a drag starts and held until it ends, so the
  // scale does not shrink under the user's finger while dragging a value that
  // sits outside the default ±10% range back toward zero. Null when idle.
  double? _dragMin;
  double? _dragMax;

  // Applies a typed premium a short while after the user stops typing, so the
  // slider tracks the field live without needing Enter (matches v1 behaviour).
  Timer? _premiumDebounce;
  static const Duration _premiumDebounceDelay = Duration(seconds: 2);

  /// The premium being typed holds a separator: not a whole percent, and
  /// said so under the field while it stands. Mirrored in
  /// [premiumInputInvalidProvider] for the form ([_setPremiumNotWhole]).
  bool _premiumNotWhole = false;

  /// The premium field's focus, so a refused Enter can hand it back.
  final FocusNode _premiumFocus = FocusNode();

  /// The sats being typed hold a separator that is not grouping: no amount,
  /// and said so under the field while it stands.
  bool _satsNotWhole = false;

  @override
  void initState() {
    super.initState();
    _premiumController = TextEditingController(
      text: ref.read(premiumValueProvider).round().toString(),
    );
    // Grouped for the locale in build, where the context is available; the
    // provider is reset on every screen open so this is normally empty.
    _satsController = TextEditingController(text: ref.read(fixedSatsProvider));
  }

  @override
  void dispose() {
    _premiumDebounce?.cancel();
    _premiumController.dispose();
    _satsController.dispose();
    _premiumFocus.dispose();
    super.dispose();
  }

  void _syncControllerFromProvider(double? prev, double next) {
    if (_editingPremium) return;
    final newText = next.round().toString();
    if (_premiumController.text != newText) {
      _premiumController.text = newText;
    }
  }

  /// Parse [v] and push it (clamped to ±[kPremiumMaxMagnitude]) to the premium
  /// provider. Returns false when [v] is empty or a lone sign so callers can
  /// decide whether to restore the field. Does not touch the controller text,
  /// so it is safe to call mid-typing.
  bool _applyPremiumText(String v) {
    final parsed = int.tryParse(v);
    if (parsed == null) return false;
    ref.read(premiumValueProvider.notifier).state = parsed
        .clamp(
          -kPremiumMaxMagnitude.toInt(),
          kPremiumMaxMagnitude.toInt(),
        )
        .toDouble();
    return true;
  }

  void _startPremiumEditing() {
    _premiumController.text = ref.read(premiumValueProvider).round().toString();
    _setPremiumNotWhole(false);
    setState(() => _editingPremium = true);
  }

  /// Whether [v] is written with a decimal separator: `1.5`, `1,`.
  static bool _hasSeparator(String v) => v.contains('.') || v.contains(',');

  /// Records whether the field holds a premium written with decimals, here
  /// and for the form: while it does, the premium the form would send is
  /// not the text on screen, so nothing may be published.
  void _setPremiumNotWhole(bool notWhole) {
    if (notWhole != _premiumNotWhole) {
      setState(() => _premiumNotWhole = notWhole);
    }
    final shared = ref.read(premiumInputInvalidProvider.notifier);
    if (shared.state != notWhole) shared.state = notWhole;
  }

  /// Finish editing the field: commit [v], or restore the text from the current
  /// premium when [v] does not parse. Cancels any pending live update.
  ///
  /// A text with decimals does not finish anything: closing the field on it
  /// would put the previous premium back out of sight — and the tap that
  /// closed it may be the one on Publish. The field stays open on what was
  /// typed, the form stays invalid, and the reason stays under it.
  void _endPremiumEditing(String v) {
    if (_hasSeparator(v)) return;
    _premiumDebounce?.cancel();
    _setPremiumNotWhole(false);
    setState(() => _editingPremium = false);
    if (!_applyPremiumText(v)) {
      _syncControllerFromProvider(null, ref.read(premiumValueProvider));
    }
  }

  /// Enter on the keyboard. A premium written with decimals is not committed
  /// and not thrown away either: the field stays open on it, with the reason
  /// under it, for the user to correct — and keeps the focus Enter took.
  void _submitPremium(String v) {
    if (_hasSeparator(v)) {
      _premiumFocus.requestFocus();
      return;
    }
    _endPremiumEditing(v);
  }

  /// The slider is the other way to set the premium: taking it closes the
  /// field, whatever it held, so the figure shown is the slider's.
  void _closePremiumFieldForSlider() {
    if (!_editingPremium) return;
    _premiumDebounce?.cancel();
    _setPremiumNotWhole(false);
    setState(() => _editingPremium = false);
    _syncControllerFromProvider(null, ref.read(premiumValueProvider));
  }

  void _onSliderChanged(double value) {
    final next = value.roundToDouble();
    final previous = ref.read(premiumValueProvider);
    // A click when the premium crosses (or lands on) zero, so the user feels
    // the neutral point without looking.
    if ((previous < 0) != (next < 0) || (previous != 0 && next == 0)) {
      HapticFeedback.selectionClick();
    }
    ref.read(premiumValueProvider.notifier).state = next;
  }

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final isMarket = ref.watch(isMarketPriceProvider);
    final isRange = ref.watch(isRangeOrderProvider);
    final l10n = AppLocalizations.of(context);

    // Sync controllers from providers via listeners (not in build body). The
    // sats one matters when the screen clears the provider on entering range
    // mode: the field must not keep showing a figure the daemon won't get.
    ref.listen<double>(premiumValueProvider, _syncControllerFromProvider);
    ref.listen<String>(fixedSatsProvider, (_, next) {
      // No sats under a text that is not a whole number is this field's own
      // doing (`onChanged`), not a clear from outside: the text stays, so
      // the user can see and correct what they typed.
      if (_satsNotWhole && next.isEmpty) return;
      final shown = _satsController.text.replaceAll(RegExp(r'\D'), '');
      if (shown != next) _satsController.text = next;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.priceSectionTitle,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textStrong,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: () => _showPriceInfo(context),
              icon: Icon(Icons.info_outline, size: 13, color: palette.textFaint),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: l10n.priceTypeInfoTooltip,
            ),
            const SizedBox(width: 8),
            PillSegmented<bool>(
              size: PillSegmentedSize.small,
              selected: isMarket,
              segments: [
                PillSegment(
                  value: true,
                  label: l10n.priceTypeMarket,
                  automationId: AutomationIds.orderCreatePriceMarket,
                ),
                // Range orders must use market price (Mostro applies a premium
                // to the variable amount), so Fixed is locked out in range.
                PillSegment(
                  value: false,
                  label: l10n.priceTypeFixed,
                  automationId: AutomationIds.orderCreatePriceFixed,
                  enabled: !isRange,
                ),
              ],
              onSelected: (market) =>
                  ref.read(isMarketPriceProvider.notifier).state = market,
            ).withAutomationId(
              AutomationIds.orderCreatePriceType,
              merge: false,
            ),
          ],
        ),
        const SizedBox(height: 11),
        if (isRange) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              l10n.fixedPriceRangeNotAvailable,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: palette.textTertiary,
              ),
            ),
          ),
        ],
        AnimatedSize(
          duration: _swapDuration,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: _swapDuration,
            child: isMarket ? _buildPremiumBlock(context) : _buildFixed(context),
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumBlock(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final create = CreateOrderPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final premium = ref.watch(premiumValueProvider);
    final side = ref.watch(orderSideProvider);
    final favour = premiumFavour(side, premium);

    final (bg, border, labelColor, valueColor) = switch (favour) {
      PremiumFavour.good => (
          create.premiumGoodBg,
          create.premiumGoodBorder,
          create.premiumGoodLabel,
          create.premiumGoodValue,
        ),
      PremiumFavour.bad => (
          create.premiumBadBg,
          create.premiumBadBorder,
          create.premiumBadLabel,
          create.premiumBadValue,
        ),
      PremiumFavour.zero => (
          create.premiumZeroBg,
          create.premiumZeroBorder,
          create.premiumZeroLabel,
          create.premiumZeroValue,
        ),
    };

    // Slider bounds default to ±10% but expand to fit a manually entered value.
    // While a drag is active the frozen bounds win, so the scale stays stable.
    final sliderMin = _dragMin ??
        (premium < -kPremiumSliderDefault ? premium : -kPremiumSliderDefault);
    final sliderMax = _dragMax ??
        (premium > kPremiumSliderDefault ? premium : kPremiumSliderDefault);
    // Whole-percent steps (Mostro rounds the premium to an integer).
    final sliderDivisions = (sliderMax - sliderMin).round().clamp(1, 2000);
    final zeroFraction =
        ((0 - sliderMin) / (sliderMax - sliderMin)).clamp(0.0, 1.0);

    final magnitude = premium.round().abs().toString();
    final String wording = switch ((side, favour)) {
      (_, PremiumFavour.zero) => l10n.premiumExactMarket,
      (OrderType.sell, PremiumFavour.good) => l10n.premiumSellAbove(magnitude),
      (OrderType.sell, PremiumFavour.bad) => l10n.premiumSellBelow(magnitude),
      (OrderType.buy, PremiumFavour.good) => l10n.premiumBuyBelow(magnitude),
      (OrderType.buy, PremiumFavour.bad) => l10n.premiumBuyAbove(magnitude),
    };

    final valueStyle = TextStyle(
      fontFamily: AppFonts.figures,
      fontSize: 19,
      fontWeight: FontWeight.w700,
      color: valueColor,
    );

    return AnimatedContainer(
      key: const ValueKey('premium-block'),
      duration: _tintDuration,
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                l10n.premiumSectionLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                ),
              ),
              const Spacer(),
              // The figure is the only way to type a premium: tapping it opens
              // the numeric keyboard in place. No second field, no pencil.
              if (_editingPremium)
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _premiumController,
                    focusNode: _premiumFocus,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    // Whole percent only: optional sign + up to 3 digits.
                    // A typed '.' or ',' is let through and kept on screen —
                    // refused as a keystroke it left the digits after it to
                    // close up, and `1.5` became 15 % — but it never reaches
                    // the premium: the field says why and waits.
                    inputFormatters: [
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        if (newValue.text.isEmpty) return newValue;
                        return RegExp(
                              r'^[+-]?\d{0,3}([.,]\d{0,2})?$',
                            ).hasMatch(newValue.text)
                            ? newValue
                            : oldValue;
                      }),
                    ],
                    textAlign: TextAlign.right,
                    style: valueStyle,
                    cursorColor: valueColor,
                    decoration: const InputDecoration(
                      isDense: true,
                      isCollapsed: true,
                      border: InputBorder.none,
                      suffixText: '%',
                    ),
                    onChanged: (v) {
                      // Live update like v1: apply the typed value a couple
                      // of seconds after the user stops typing, so the slider
                      // follows without needing Enter. The controller is left
                      // untouched here, so the cursor and in-progress text
                      // are never disturbed.
                      _premiumDebounce?.cancel();
                      final notWhole = _hasSeparator(v);
                      _setPremiumNotWhole(notWhole);
                      // With decimals there is nothing to apply: the premium
                      // stays what it was until the text is a whole percent.
                      if (notWhole) return;
                      _premiumDebounce = Timer(
                        _premiumDebounceDelay,
                        () => _applyPremiumText(v),
                      );
                    },
                    onSubmitted: _submitPremium,
                    onTapOutside: (_) =>
                        _endPremiumEditing(_premiumController.text),
                  ),
                ).withAutomationId(AutomationIds.orderCreatePremium)
              else
                InkWell(
                  key: const ValueKey('premium-figure'),
                  onTap: _startPremiumEditing,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(formatPremium(premium), style: valueStyle),
                  ),
                ).withAutomationId(AutomationIds.orderCreatePremium),
            ],
          ),
          if (_editingPremium && _premiumNotWhole) ...[
            const SizedBox(height: 6),
            Text(
              l10n.orderPremiumMustBeWhole,
              key: const ValueKey('premium-not-whole'),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, height: 1.4, color: create.error),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 28,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                activeTrackColor: valueColor,
                inactiveTrackColor: create.sliderTrack,
                thumbColor: valueColor,
                overlayShape: SliderComponentShape.noOverlay,
                trackShape: PremiumTrackShape(
                  zeroFraction: zeroFraction,
                  zeroMarkColor: create.sliderZeroMark,
                  showFill: favour != PremiumFavour.zero,
                ),
                thumbShape: const PremiumThumbShape(),
                tickMarkShape: SliderTickMarkShape.noTickMark,
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: Slider(
                value: premium.clamp(sliderMin, sliderMax),
                min: sliderMin,
                max: sliderMax,
                divisions: sliderDivisions,
                label: formatPremium(premium),
                onChangeStart: (_) {
                  _closePremiumFieldForSlider();
                  setState(() {
                    _dragMin = sliderMin;
                    _dragMax = sliderMax;
                  });
                },
                onChanged: _onSliderChanged,
                onChangeEnd: (_) => setState(() {
                  _dragMin = null;
                  _dragMax = null;
                }),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${sliderMin.round()}%',
                style: TextStyle(fontSize: 10, color: palette.textTertiary),
              ),
              Expanded(
                child: Text(
                  wording,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: palette.textFaint),
                ),
              ),
              Text(
                '+${sliderMax.round()}%',
                style: TextStyle(fontSize: 10, color: palette.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFixed(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final symbols = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    ).symbols;

    return Column(
      key: const ValueKey('fixed-block'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UnderlineAmountField(
          controller: _satsController,
          hintText: '0',
          keyboardType: TextInputType.number,
          inputFormatters: [
            // Sats are whole. A separator the user types stays on screen,
            // as in the fiat fields: dropped, `1000.5` closed up into
            // 10 005 sats.
            ThousandsInputFormatter(
              groupSeparator: symbols.GROUP_SEP,
              decimalSeparator: symbols.DECIMAL_SEP,
              allowDecimals: false,
              keepTypedSeparators: true,
            ),
          ],
          hasError: _satsNotWhole,
          trailing: Text(
            l10n.satsUnitLabel,
            style: TextStyle(fontSize: 13, color: palette.textTertiary),
          ),
          onChanged: (v) {
            final notWhole = amountHasTypedSeparator(
              v,
              groupSeparator: symbols.GROUP_SEP,
              decimalSeparator: symbols.DECIMAL_SEP,
            );
            if (notWhole != _satsNotWhole) {
              setState(() => _satsNotWhole = notWhole);
            }
            // No digits out of a text that is not a whole number: the form
            // then has no fixed price to publish.
            ref.read(fixedSatsProvider.notifier).state = notWhole
                ? ''
                : v.replaceAll(RegExp(r'\D'), '');
          },
        ).withAutomationId(AutomationIds.orderCreateSatsAmount),
        if (_satsNotWhole) ...[
          const SizedBox(height: 6),
          Text(
            l10n.orderAmountMustBeWhole,
            key: const ValueKey('sats-not-whole'),
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: CreateOrderPalette.of(context).error,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          l10n.fixedPriceNote,
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: palette.textTertiary,
          ),
        ),
      ],
    );
  }

  void _showPriceInfo(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showMostroDialog<void>(
      context: context,
      builder: (dialogContext) => MostroDialog(
        title: l10n.priceTypesDialogTitle,
        body: l10n.priceTypesDialogContent,
        primary: ModalAction(
          label: l10n.okButtonLabel,
          onPressed: () => Navigator.pop(dialogContext),
        ),
      ),
    );
  }
}
