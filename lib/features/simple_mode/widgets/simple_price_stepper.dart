import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/order/widgets/price_section.dart'
    show formatPremium;
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Whose order the price is set on. The premium is one number on the wire;
/// what it means is said from the side of whoever sets it.
enum PriceSide { seller, buyer }

/// What [premium] means to whoever sets it on [side], in words.
///
/// Said in sats, because that is what the node does with a premium — it
/// takes that percent off the sats — and so is exact at every figure. "The
/// buyer pays 10 % more" is not: the same money for 10 % fewer sats is a
/// coin 11.1 % dearer, and the price printed beside the sentence says so.
String priceMeaning(
  AppLocalizations l10n, {
  required PriceSide side,
  required int premium,
}) {
  final percent = '${premium.abs()}';
  return switch (side) {
    PriceSide.seller =>
      premium == 0
          ? l10n.simplePriceSellMarket
          : premium > 0
          ? l10n.simplePriceSellAbove(percent)
          : l10n.simplePriceSellBelow(percent),
    PriceSide.buyer =>
      premium == 0
          ? l10n.simplePriceBuyMarket
          : premium > 0
          ? l10n.simplePriceBuyAbove(percent)
          : l10n.simplePriceBuyBelow(percent),
  };
}

/// The colour of [premium]'s figure for whoever sets it on [side]: lime
/// where it favours them — a seller asking for more, a buyer asking for
/// less — and the warning colour where it costs them. A discount set by a
/// slip of the finger should not look like the default.
Color priceFigureColor(
  OrderBookPalette pal, {
  required PriceSide side,
  required int premium,
}) {
  if (premium == 0) return pal.textSecondary;
  final favourable = side == PriceSide.seller ? premium > 0 : premium < 0;
  return favourable ? pal.limeText : Colors.amber;
}

/// The price of a Simple Mode order against the market, on one row: a step
/// down, the figure, a step up.
///
/// A whole percent either side of the market ([simplePremiumLimit]) — a seller
/// can ask for more or sell at a discount, a buyer can offer more or ask
/// for less. Under the row, what the figure means in words and, away from
/// the market, the price of one BTC it comes to.
class SimplePriceStepper extends StatelessWidget {
  const SimplePriceStepper({
    super.key,
    required this.premium,
    required this.onStep,
    required this.side,
    required this.rate,
    required this.currency,
  });

  /// The order's premium, a whole percent: the share taken off the sats.
  final int premium;

  /// A tap on a button: one percent down (`-1`) or up (`1`). The step and
  /// not the figure it leads to, which whoever holds the premium works out
  /// from what it is when the tap lands ([steppedPremium]) — from the
  /// figure this frame was built with, the second of two quick taps would
  /// repeat the first.
  final ValueChanged<int> onStep;
  final PriceSide side;

  /// The market's price of one BTC in [currency], null while unknown.
  final double? rate;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final meaning = priceMeaning(l10n, side: side, premium: premium);
    final figureColor = priceFigureColor(pal, side: side, premium: premium);
    final price =
        premium == 0 ? null : priceWithPremium(rate: rate, premium: premium);
    // No-break spaces: the price wraps to the next line whole, never with
    // its `1` left behind at the end of the sentence.
    final priceText =
        price == null
            ? null
            : '1\u00A0BTC\u00A0≈\u00A0${NumberFormat('#,##0.00', Localizations.localeOf(context).toString()).format(price)}\u00A0$currency';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      decoration: BoxDecoration(
        color: pal.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pal.navBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.percent_rounded, size: 18, color: pal.limeText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.simplePriceLabel,
                  style: TextStyle(
                    color: pal.textTitle,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              _StepButton(
                key: const ValueKey('simple-price-lower'),
                plus: false,
                tooltip: l10n.simplePriceLower,
                onPressed:
                    premium > -simplePremiumLimit ? () => onStep(-1) : null,
              ),
              // A fixed width: the buttons stay where the finger is while
              // the figure between them changes length.
              SizedBox(
                width: 84,
                child: Text(
                  premium == 0
                      ? l10n.simplePriceMarket
                      : formatPremium(premium.toDouble()),
                  key: const ValueKey('simple-price-figure'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: figureColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              _StepButton(
                key: const ValueKey('simple-price-raise'),
                plus: true,
                tooltip: l10n.simplePriceRaise,
                onPressed:
                    premium < simplePremiumLimit ? () => onStep(1) : null,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              priceText == null ? meaning : '$meaning $priceText',
              key: const ValueKey('simple-price-meaning'),
              style: TextStyle(
                color: pal.textTertiary,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One step of the price, a round button the size of a fingertip. Off at
/// the end of the control's reach.
class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.plus,
    required this.tooltip,
    required this.onPressed,
  });

  /// A step up (`+`) or a step down (`−`).
  final bool plus;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);

    return IconButton(
      icon: _StepSign(plus: plus),
      tooltip: tooltip,
      onPressed: onPressed,
      color: pal.limeText,
      disabledColor: pal.textTertiary,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      style: IconButton.styleFrom(
        side: BorderSide(color: pal.navBorder),
        shape: const CircleBorder(),
      ),
    );
  }
}

/// The sign on a step button, drawn as one bar or two.
///
/// Not a glyph of the icon font. On the web that font is cut down, build by
/// build, to the icons the build uses, and a browser can hold the one from
/// before a deploy: the minus sign was new with this control, and where the
/// old font was still in use the button to sell at a discount showed
/// nothing in it. The sign that changes a price is not left to that.
class _StepSign extends StatelessWidget {
  const _StepSign({required this.plus});

  final bool plus;

  static const double _length = 14;
  static const double _thickness = 2.4;

  @override
  Widget build(BuildContext context) {
    // The button's own colour for its state: lime, or the faded one when
    // the control has reached its limit.
    final color = IconTheme.of(context).color;
    Widget bar({required bool upright}) => Container(
      width: upright ? _thickness : _length,
      height: upright ? _length : _thickness,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(_thickness / 2),
      ),
    );

    return SizedBox.square(
      dimension: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [bar(upright: false), if (plus) bar(upright: true)],
      ),
    );
  }
}
