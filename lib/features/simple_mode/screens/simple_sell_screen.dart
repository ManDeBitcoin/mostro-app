import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/models/order_detail_rules.dart'
    show estimateSats;
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/models/payment_details_rules.dart';
import 'package:mostro/features/simple_mode/models/payment_method_groups.dart'
    show methodsOf;
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/features/simple_mode/providers/payment_method_providers.dart';
import 'package:mostro/features/simple_mode/providers/simple_identity_provider.dart';
import 'package:mostro/features/simple_mode/widgets/payment_details_editor.dart';
import 'package:mostro/features/simple_mode/widgets/payment_method_field.dart';
import 'package:mostro/features/simple_mode/widgets/simple_price_stepper.dart';
import 'package:mostro/features/simple_mode/widgets/simple_sell_confirm_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/shared/utils/whole_amount_input.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';

/// Simple Mode: Amount-first Sell Wizard.
/// 1. Amount input with live Satoshi conversion
/// 2. The price against the market: a premium, a discount, or neither
/// 3. Payment methods: the community's, any number of them, picked by category
/// 4. The seller's payment details, a field to each ticked method: kept on
///    the device, never part of the order
/// 5. Explanatory stages of security escrow
/// 6. Bottom sheet confirmation summary before publishing offer
class SimpleSellScreen extends ConsumerStatefulWidget {
  const SimpleSellScreen({super.key});

  @override
  ConsumerState<SimpleSellScreen> createState() => _SimpleSellScreenState();
}

class _SimpleSellScreenState extends ConsumerState<SimpleSellScreen> {
  final _amountController = TextEditingController(text: '100');

  /// What the payment-details fields hold, as they last reported it.
  List<PaymentDetailsEntry> _details = const [];

  /// The order's premium, a whole percent either side of the market.
  int _premium = 0;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _openConfirmSheet({
    required double fiatAmount,
    required String fiatCode,
    required List<String> paymentMethods,
    required List<PaymentDetailsEntry> paymentDetails,
    required double premium,
    required int? estimatedSats,
  }) {
    showMostroSheet(
      context: context,
      builder: (_) => SimpleSellConfirmSheet(
        fiatAmount: fiatAmount,
        fiatCode: fiatCode,
        paymentMethods: paymentMethods,
        paymentDetails: paymentDetails,
        premium: premium,
        estimatedSats: estimatedSats,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final currency = ref.watch(simpleCurrencyProvider);

    // Live exchange rate & Satoshi estimation
    final rateAsync = ref.watch(exchangeRateProvider(currency));
    final rate = rateAsync.valueOrNull;
    // A whole amount or nothing: the order cannot carry decimals, and an
    // unreadable field is not an order for some default.
    final int? amount = wholeFiatAmount(_amountController.text);
    final int? estimatedSats = amount == null
        ? null
        : estimateSats(
            fiat: amount.toDouble(),
            rate: rate,
            premium: _premium.toDouble(),
          );

    // What the seller ticked, of the community's own list. That list can
    // change while the screen is up — the card arrives after startup, the
    // operator edits it — and a method that left it is no longer offered.
    // None stands in for it, and none stands before the first tick either:
    // an order names a way to be paid only if the seller chose it, so with
    // nothing ticked nothing can be published.
    final paymentMethods = tickedMethods(
      methodsOf(ref.watch(sellMethodGroupsProvider)),
      ref.watch(sellTickedMethodsProvider),
    );

    final allOrders = ref.watch(orderBookProvider).valueOrNull ?? [];
    final matchingBuyOrders = allOrders
        .where((o) => isOfferedInSimpleMode(o, kind: 'buy', currency: currency))
        .toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      children: [
        // Title
        Text(
          SimpleL10n.howMuchSell(context),
          style: theme.textTheme.titleLarge?.copyWith(
            color: pal.textTitle,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Market Reference Rate Card
        if (rate != null && rate > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: pal.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: pal.navBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.candlestick_chart_outlined,
                  color: pal.limeText,
                  size: 18,
                ),
                const SizedBox(width: 8),
                // A Wrap: on a narrow phone the price drops to a line of
                // its own instead of running off the card.
                Expanded(
                  child: Wrap(
                    children: [
                      Text(
                        '${SimpleL10n.referencePrice(context)}: ',
                        style: TextStyle(
                          color: pal.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '1 BTC ≈ ${NumberFormat('#,##0.00', Localizations.localeOf(context).toString()).format(rate)} $currency',
                        style: TextStyle(
                          color: pal.limeText,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Amount card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.surfaceCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: pal.navBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    currency,
                    style: TextStyle(
                      color: pal.limeText,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [wholeAmountInputFormatter],
                      style: TextStyle(
                        color: pal.textTitle,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Satoshi live conversion readout
              Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 16, color: pal.limeText),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      amount == null
                          ? l10n.orderAmountMustBeWhole
                          : estimatedSats != null
                          ? '≈ $estimatedSats sats'
                          : (rateAsync.isLoading
                                ? SimpleL10n.calculatingRate(context)
                                : 'Cotización al cambio del mercado'),
                      // Unclipped, and in the warning colour while it is
                      // the reason nothing can be published.
                      style: TextStyle(
                        color: amount == null ? Colors.amber : pal.limeText,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Preset chips
              Wrap(
                spacing: 8,
                children: ['50', '100', '250', '500'].map((val) {
                  final isSelected = _amountController.text == val;
                  return ChoiceChip(
                    label: Text('$val $currency'),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        _amountController.text = val;
                      });
                    },
                    selectedColor: pal.limeBorder,
                    labelStyle: TextStyle(
                      color: isSelected ? pal.limeText : pal.textSecondary,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // The price against the market: a step down, the figure, a step up.
        SimplePriceStepper(
          premium: _premium,
          onStep: (step) =>
              setState(() => _premium = steppedPremium(_premium, step)),
          side: PriceSide.seller,
          rate: rate,
          currency: currency,
        ),

        const SizedBox(height: 20),

        // Payment Method Selector
        Text(
          SimpleL10n.selectReceiveMethod(context),
          style: theme.textTheme.titleMedium?.copyWith(
            color: pal.textTitle,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        PaymentMethodField(
          groups: sellMethodGroupsProvider,
          ticked: sellTickedMethodsProvider,
          placeholder: l10n.simpleMethodsChoose,
          hint: l10n.simpleMethodsSellHint,
        ),

        const SizedBox(height: 20),

        // The seller's payment details. Not part of the order — an order is
        // public — and not a draft of this one either: the fields are the
        // device's copy, a field to a method, and the trade view sends them
        // to the buyer once the escrow is locked.
        Text(
          SimpleL10n.paymentDetailsPrompt(context),
          style: theme.textTheme.titleMedium?.copyWith(
            color: pal.textTitle,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.simplePayDetailsLocalNote,
          style: TextStyle(color: pal.textTertiary, fontSize: 12, height: 1.3),
        ),
        const SizedBox(height: 10),
        // A field to each ticked method, and none before the first tick:
        // there is no account to ask for until the seller says how they
        // are paid.
        if (paymentMethods.isEmpty)
          Text(
            l10n.simplePayDetailsPickFirst,
            style: TextStyle(color: pal.textSecondary, fontSize: 13),
          )
        else
          PaymentDetailsEditor(
            methods: paymentMethods,
            onChanged: (entries) => setState(() => _details = entries),
          ),

        const SizedBox(height: 24),

        // Steps Explanation
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.navBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                SimpleL10n.sellStepsTitle(context),
                style: TextStyle(
                  color: pal.textTitle,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              _buildStepRow(
                icon: Icons.lock_outline_rounded,
                text: '1. Bloqueas Bitcoin en custodia temporal',
                pal: pal,
              ),
              const SizedBox(height: 8),
              _buildStepRow(
                icon: Icons.person_search_rounded,
                text: '2. Un comprador acepta tu oferta',
                pal: pal,
              ),
              const SizedBox(height: 8),
              _buildStepRow(
                icon: Icons.account_balance_rounded,
                text: '3. Recibes el dinero en tu cuenta bancaria',
                pal: pal,
              ),
              const SizedBox(height: 8),
              _buildStepRow(
                icon: Icons.check_circle_outline_rounded,
                text: '4. Confirmas la recepción y liberas el Bitcoin',
                pal: pal,
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Why the button below is off, said next to it: by here the amount
        // card and its own line are a screen away.
        if (amount == null || paymentMethods.isEmpty) ...[
          Text(
            amount == null
                ? l10n.orderAmountMustBeWhole
                : l10n.simpleMethodsChooseOne,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.amber, fontSize: 13),
          ),
          const SizedBox(height: 10),
        ],

        // Publish Button
        FilledButton.icon(
          onPressed: amount == null || paymentMethods.isEmpty
              ? null
              : () {
                  _openConfirmSheet(
                    fiatAmount: amount.toDouble(),
                    fiatCode: currency,
                    paymentMethods: paymentMethods,
                    // Of what the fields hold, what belongs to the methods
                    // on the order: a field that just left the screen may
                    // not have reported yet.
                    paymentDetails: paymentDetailsToSend(
                      _details.where(
                        (entry) => paymentMethods.any(
                          (method) =>
                              paymentMethodKey(method) ==
                              paymentMethodKey(entry.method),
                        ),
                      ),
                    ),
                    premium: _premium.toDouble(),
                    estimatedSats: estimatedSats,
                  );
                },
          icon: const Icon(Icons.arrow_upward_rounded),
          label: Text(
            SimpleL10n.publishOffer(context),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: pal.limeText,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        // Active buyers section
        if (matchingBuyOrders.isNotEmpty) ...[
          const SizedBox(height: 28),
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 20, color: pal.limeText),
              const SizedBox(width: 8),
              Text(
                'Compradores activos en el mercado',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: pal.textTitle,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...matchingBuyOrders.map(
            (order) => _BuyerOfferCard(
              order: order,
              currency: currency,
              pal: pal,
              onSellPressed: () => context.push(AppRoute.takeBuyPath(order.id)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStepRow({
    required IconData icon,
    required String text,
    required OrderBookPalette pal,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: pal.limeText),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: pal.textSecondary, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _BuyerOfferCard extends ConsumerWidget {
  const _BuyerOfferCard({
    required this.order,
    required this.currency,
    required this.pal,
    required this.onSellPressed,
  });

  final OrderItem order;
  final String currency;
  final OrderBookPalette pal;
  final VoidCallback onSellPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myPubkey = ref.watch(myPubkeyProvider).valueOrNull;
    final isMyOrder =
        order.isMine || (myPubkey != null && order.creatorPubkey == myPubkey);
    final nym = isMyOrder && myPubkey != null
        ? ref.watch(peerNymProvider(myPubkey)).valueOrNull
        : ref.watch(peerNymProvider(order.creatorPubkey)).valueOrNull;

    final displayName = isMyOrder
        ? '${nym?.pseudonym ?? "Tú"} ${SimpleL10n.yourOffer(context)}'
        : (nym?.pseudonym ?? (order.kind == 'sell' ? 'Vendedor' : 'Comprador'));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: pal.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: pal.navBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (nym != null)
                  NymAvatar(
                    iconIndex: nym.iconIndex,
                    colorHue: nym.colorHue,
                    size: 36,
                  )
                else
                  CircleAvatar(
                    backgroundColor: pal.navBorder,
                    radius: 18,
                    child: Icon(Icons.person, size: 18, color: pal.limeText),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              style: TextStyle(
                                color: pal.textTitle,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: order.isRange
                                  ? pal.limeBorder.withValues(alpha: 0.15)
                                  : pal.navBorder,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              order.isRange
                                  ? SimpleL10n.rangeOrder(context)
                                  : SimpleL10n.fixedOrder(context),
                              style: TextStyle(
                                color: order.isRange
                                    ? pal.limeText
                                    : pal.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        // The star stays on the first line when the text
                        // beside it takes two.
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: order.rating > 0
                                ? Colors.amber
                                : pal.textTertiary,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          if (order.tradeCount > 0) ...[
                            Text(
                              order.rating.toStringAsFixed(1),
                              style: TextStyle(
                                color: pal.textTitle,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            // Flexible, so it wraps: beside the
                            // amount this line has less room than it
                            // needs on a narrow phone, and ran over it.
                            Flexible(
                              child: Text(
                                ' (${SimpleL10n.counterpartyTrades(order.tradeCount, context)} · ${SimpleL10n.daysActive(order.daysActive, context)})',
                                style: TextStyle(
                                  color: pal.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ] else ...[
                            Flexible(
                              child: Text(
                                '${SimpleL10n.newTrader(context)} · ${SimpleL10n.daysActive(order.daysActive, context)}',
                                style: TextStyle(
                                  color: pal.textTertiary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  order.isRange
                      ? '${order.fiatAmountMin?.toInt()} – ${order.fiatAmountMax?.toInt()} ${order.fiatCode}'
                      : '${order.fiatAmount?.toInt()} ${order.fiatCode}',
                  style: TextStyle(
                    color: pal.limeText,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            // Premium tag. Read from the side of the seller looking at it:
            // a buyer who pays over the market is the better offer here,
            // where on the Buy tab it is the dearer one.
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: pal.surfaceCard,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    order.premium <= 0
                        ? Icons.trending_down
                        : Icons.trending_up,
                    size: 13,
                    color: order.premium >= 0
                        ? pal.limeText
                        : Colors.orangeAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    order.premium == 0
                        ? SimpleL10n.marketRateZero(context)
                        : (order.premium > 0
                              ? SimpleL10n.premiumAbove(
                                  order.premium.toStringAsFixed(1),
                                  context,
                                )
                              : SimpleL10n.premiumBelow(
                                  order.premium.toStringAsFixed(1),
                                  context,
                                )),
                    style: TextStyle(
                      fontSize: 11,
                      color: order.premium >= 0
                          ? pal.limeText
                          : Colors.orangeAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            // On lines of its own: a buyer can offer several methods, and
            // which ones is what the seller is reading for. Eight lines
            // hold the community's whole list on the narrowest phone; the
            // limit is for an order written to fill the screen.
            Text(
              'Paga con: ${order.paymentMethod}',
              style: TextStyle(color: pal.textSecondary, fontSize: 13),
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onSellPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: pal.limeText,
                  foregroundColor: Colors.black,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text(
                  'Vender a este comprador',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
