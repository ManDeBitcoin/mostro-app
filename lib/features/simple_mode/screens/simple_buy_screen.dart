import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/models/bond_rules.dart'
    show bondSharePercent;
import 'package:mostro/features/order/models/create_order_rules.dart'
    show takerBondApplies;
import 'package:mostro/features/order/models/order_detail_rules.dart'
    show estimateSats;
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/models/payment_method_groups.dart'
    show methodsOf;
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/features/simple_mode/providers/payment_method_providers.dart';
import 'package:mostro/features/simple_mode/providers/simple_identity_provider.dart';
import 'package:mostro/features/simple_mode/widgets/payment_method_field.dart';
import 'package:mostro/features/simple_mode/widgets/simple_buy_confirm_sheet.dart';
import 'package:mostro/features/simple_mode/widgets/simple_buy_order_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/shared/utils/whole_amount_input.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';

/// Simple Mode: Amount-first Buy Wizard.
/// 1. Amount input with live Satoshi conversion
/// 2. Payment methods to filter the offers by, picked by category
/// 3. Filtered sellers list with humanized reputation and refundable guarantee
/// 4. Bottom sheet confirmation summary before taking order
///
/// And, for a buyer none of those offers suits, a way to publish a buy
/// order of their own for the amount and the methods already on the tab
/// ([SimpleBuyOrderSheet]).
class SimpleBuyScreen extends ConsumerStatefulWidget {
  const SimpleBuyScreen({super.key});

  @override
  ConsumerState<SimpleBuyScreen> createState() => _SimpleBuyScreenState();
}

class _SimpleBuyScreenState extends ConsumerState<SimpleBuyScreen> {
  final _amountController = TextEditingController(text: '50');
  bool _filterMatchingOnly = true;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _openConfirmSheet({
    required OrderItem order,
    required double fiatAmount,
    required String fiatCode,
    required int? estimatedSats,
  }) {
    showMostroSheet(
      context: context,
      builder: (_) => SimpleBuyConfirmSheet(
        order: order,
        fiatAmount: fiatAmount,
        fiatCode: fiatCode,
        estimatedSats: estimatedSats,
      ),
    );
  }

  void _openBuyOrderSheet({required int? fiatAmount}) {
    // The amount field would take the focus back when the sheet closes,
    // and its keyboard would come up over the sheet's own picker.
    FocusManager.instance.primaryFocus?.unfocus();
    showMostroSheet(
      context: context,
      builder: (_) => SimpleBuyOrderSheet(fiatAmount: fiatAmount),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // The node's own word, never a default: its bond policy. With bonds
    // off, or before the node has said, no deposit is announced.
    final node = ref.watch(mostroNodeProvider).valueOrNull;
    final currency = ref.watch(simpleCurrencyProvider);

    // Live exchange rate & Sats calculation
    final rateAsync = ref.watch(exchangeRateProvider(currency));
    final rate = rateAsync.valueOrNull;
    // A whole amount or nothing: a take cannot carry decimals.
    final int? typedAmount = wholeFiatAmount(_amountController.text);
    final int? estimatedSats = typedAmount == null
        ? null
        : estimateSats(fiat: typedAmount.toDouble(), rate: rate, premium: 0);

    final takerBondPercent =
        takerBondApplies(policy: node?.bondPolicy, applyTo: node?.bondApplyTo)
        ? bondSharePercent(node?.bondAmountPct)
        : null;

    final offers = ref.watch(simpleSellOffersProvider);
    // What the buyer ticked, of the community's own methods and whatever
    // else the offers carry. Nothing ticked is every method, so no offer is
    // hidden behind a method the list does not know. A ticked method that
    // left the list — its last offer was taken — filters nothing any more.
    final paymentMethods = tickedMethods(
      methodsOf(ref.watch(buyMethodGroupsProvider)),
      ref.watch(buyTickedMethodsProvider),
    );
    final allSellOrders = offers
        .where((o) => isPaidByAny(o, paymentMethods))
        .toList();

    bool matchesAmount(OrderItem o) {
      if (typedAmount == null) return true;
      if (o.isRange) return takeAmountFor(o, typedAmount) != null;
      return o.fiatAmount == typedAmount;
    }

    final matchingSellOrders = allSellOrders.where(matchesAmount).toList();
    final displayedSellOrders = (_filterMatchingOnly && typedAmount != null)
        ? matchingSellOrders
        : allSellOrders;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      children: [
        // Title
        Text(
          SimpleL10n.howMuchBuy(context),
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
                      typedAmount == null
                          ? l10n.orderAmountMustBeWhole
                          : estimatedSats != null
                          ? '≈ $estimatedSats sats'
                          : (rateAsync.isLoading
                                ? SimpleL10n.calculatingRate(context)
                                : 'Recibirás Bitcoin al cambio del mercado'),
                      // Unclipped, and in the warning colour while the
                      // field holds no amount an order can carry.
                      style: TextStyle(
                        color: typedAmount == null
                            ? Colors.amber
                            : pal.limeText,
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
                children: ['20', '50', '100', '200'].map((val) {
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

        // Payment Method Selector
        Text(
          SimpleL10n.selectPaymentMethod(context),
          style: theme.textTheme.titleMedium?.copyWith(
            color: pal.textTitle,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        PaymentMethodField(
          groups: buyMethodGroupsProvider,
          ticked: buyTickedMethodsProvider,
          placeholder: l10n.simpleMethodsAny,
          hint: l10n.simpleMethodsBuyHint,
          offers: buyOffersByMethodProvider,
        ),

        const SizedBox(height: 20),

        // What this node asks takers to lock first, when it asks anything.
        if (takerBondPercent != null)
          Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: pal.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: pal.navBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: pal.limeText, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${SimpleL10n.temporaryGuarantee(context)}: $takerBondPercent %',
                      style: TextStyle(
                        color: pal.textTitle,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      SimpleL10n.temporaryGuaranteeTooltip(context),
                      style: TextStyle(color: pal.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Sellers List Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              SimpleL10n.viewOffers(context),
              style: theme.textTheme.titleMedium?.copyWith(
                color: pal.textTitle,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (allSellOrders.length != matchingSellOrders.length &&
                typedAmount != null)
              TextButton(
                onPressed: () =>
                    setState(() => _filterMatchingOnly = !_filterMatchingOnly),
                child: Text(
                  _filterMatchingOnly
                      ? '${SimpleL10n.showAllOffers(context)} (${allSellOrders.length})'
                      : '${SimpleL10n.matchingOffers(context)} (${matchingSellOrders.length})',
                  style: TextStyle(
                    fontSize: 12,
                    color: pal.limeText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (displayedSellOrders.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: pal.surfaceCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 40,
                  color: pal.textTertiary,
                ),
                const SizedBox(height: 12),
                Text(
                  'No hay vendedores activos con estos filtros.',
                  style: TextStyle(color: pal.textSecondary),
                ),
                if (_filterMatchingOnly && allSellOrders.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        setState(() => _filterMatchingOnly = false),
                    child: Text(
                      '${SimpleL10n.showAllOffers(context)} (${allSellOrders.length})',
                      style: TextStyle(
                        color: pal.limeText,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  l10n.simpleBuyOrderEmptyHint,
                  style: TextStyle(color: pal.textTertiary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('simple-buy-order-empty'),
                  onPressed: () => _openBuyOrderSheet(fiatAmount: typedAmount),
                  icon: const Icon(Icons.campaign_outlined, size: 18),
                  // Not the sheet's own "publish": this opens it, and
                  // nothing goes out before the button at its foot.
                  label: Text(
                    l10n.simpleBuyOrderOpen,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: pal.limeText,
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            ),
          )
        else ...[
          // Above the offers, not under them: with a dozen on the list a
          // buyer none of them suits would never scroll to it.
          _OwnOrderRow(
            pal: pal,
            onTap: () => _openBuyOrderSheet(fiatAmount: typedAmount),
          ),
          const SizedBox(height: 12),
          ...displayedSellOrders.map((order) {
            final isRange = order.isRange;
            // A fixed order is taken for its own amount; a range order for
            // the amount typed, and not at all until that is a whole amount
            // inside its limits.
            final int? takeAmount = takeAmountFor(order, typedAmount);
            // The seller's own sats when the order fixes them; otherwise
            // what the node would price the amount at with this order's
            // premium.
            final int? fixedSats = order.amountSats?.toInt();
            final int? orderEstimatedSats = (fixedSats != null && fixedSats > 0)
                ? fixedSats
                : takeAmount == null
                ? null
                : estimateSats(
                    fiat: takeAmount.toDouble(),
                    rate: rate,
                    premium: order.premium,
                  );
            final bool amountMismatched =
                !isRange &&
                typedAmount != null &&
                typedAmount != order.fiatAmount;

            return _SellerOfferCard(
              order: order,
              isRange: isRange,
              takeAmount: takeAmount,
              orderEstimatedSats: orderEstimatedSats,
              amountMismatched: amountMismatched,
              currency: currency,
              pal: pal,
              onBuyPressed: takeAmount == null
                  ? null
                  : () {
                      _openConfirmSheet(
                        order: order,
                        fiatAmount: takeAmount.toDouble(),
                        fiatCode: currency,
                        estimatedSats: orderEstimatedSats,
                      );
                    },
            );
          }),
        ],
      ],
    );
  }
}

/// The way to a buy order of one's own, a line above the offers: the
/// question a buyer scanning them is asking, and what to do about it.
class _OwnOrderRow extends StatelessWidget {
  const _OwnOrderRow({required this.pal, required this.onTap});

  final OrderBookPalette pal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Material(
      color: pal.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: pal.navBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: InkWell(
          key: const ValueKey('simple-buy-order-row'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Icon(Icons.campaign_outlined, size: 20, color: pal.limeText),
                  const SizedBox(width: 10),
                  // A Wrap: on a narrow phone, or in a longer language, the
                  // action drops under the question instead of being cut.
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l10n.simpleBuyOrderPrompt,
                          style: TextStyle(
                            color: pal.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          l10n.simpleBuyOrderPromptAction,
                          style: TextStyle(
                            color: pal.limeText,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
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
    );
  }
}

class _SellerOfferCard extends ConsumerWidget {
  const _SellerOfferCard({
    required this.order,
    required this.isRange,
    required this.takeAmount,
    required this.orderEstimatedSats,
    required this.amountMismatched,
    required this.currency,
    required this.pal,
    required this.onBuyPressed,
  });

  final OrderItem order;
  final bool isRange;

  /// The whole amount the order would be taken for, or null for a range
  /// order while the amount typed is not one inside its limits.
  final int? takeAmount;
  final int? orderEstimatedSats;
  final bool amountMismatched;
  final String currency;
  final OrderBookPalette pal;

  /// Null while the order cannot be taken ([takeAmount] is null).
  final VoidCallback? onBuyPressed;

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
                              color: isRange
                                  ? pal.limeBorder.withValues(alpha: 0.15)
                                  : pal.navBorder,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isRange
                                  ? SimpleL10n.rangeOrder(context)
                                  : SimpleL10n.fixedOrder(context),
                              style: TextStyle(
                                color: isRange
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isRange
                          ? '${order.fiatAmountMin?.toInt()} – ${order.fiatAmountMax?.toInt()} ${order.fiatCode}'
                          : '${order.fiatAmount?.toInt()} ${order.fiatCode}',
                      style: TextStyle(
                        color: pal.limeText,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (isRange && takeAmount != null)
                      Text(
                        'Comprarás: $takeAmount ${order.fiatCode}',
                        style: TextStyle(
                          color: pal.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            // Premium & Rate Tag
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
                    color: order.premium <= 0
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
                      color: order.premium <= 0
                          ? pal.limeText
                          : Colors.orangeAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (orderEstimatedSats != null) ...[
                    Text(
                      ' · ≈ $orderEstimatedSats sats',
                      style: TextStyle(fontSize: 11, color: pal.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            if (isRange && takeAmount == null) ...[
              const SizedBox(height: 10),
              Text(
                AppLocalizations.of(context).simpleRangeAmountHint(
                  '${order.fiatAmountMin?.toInt()}',
                  '${order.fiatAmountMax?.toInt()}',
                  order.fiatCode,
                ),
                style: const TextStyle(fontSize: 11, color: Colors.amber),
              ),
            ],
            if (amountMismatched) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Esta orden es de monto fijo (${order.fiatAmount?.toInt()} ${order.fiatCode}). Para tomarla, debes comprar el total.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(height: 20),
            // On lines of its own: an offer can take several methods, and
            // which ones is what the buyer is reading for. Eight lines hold
            // the community's whole list on the narrowest phone; the limit
            // is for an order written to fill the screen.
            Text(
              'Pago: ${order.paymentMethod}',
              style: TextStyle(color: pal.textSecondary, fontSize: 13),
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onBuyPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: pal.limeText,
                  foregroundColor: Colors.black,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  takeAmount == null
                      ? SimpleL10n.buyButton(context)
                      : '${SimpleL10n.buyButton(context)} $takeAmount $currency',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
