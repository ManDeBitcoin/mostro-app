import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';
import 'package:mostro/features/simple_mode/providers/simple_identity_provider.dart';
import 'package:mostro/features/simple_mode/widgets/simple_buy_confirm_sheet.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';

/// Simple Mode: Amount-first Buy Wizard.
/// 1. Amount input with live Satoshi conversion
/// 2. Payment method selector (filtered by community if active)
/// 3. Filtered sellers list with humanized reputation and refundable guarantee
/// 4. Bottom sheet confirmation summary before taking order
class SimpleBuyScreen extends ConsumerStatefulWidget {
  const SimpleBuyScreen({super.key});

  @override
  ConsumerState<SimpleBuyScreen> createState() => _SimpleBuyScreenState();
}

class _SimpleBuyScreenState extends ConsumerState<SimpleBuyScreen> {
  final _amountController = TextEditingController(text: '50');
  String? _selectedMethod;
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
    required int bondPercent,
  }) {
    showMostroSheet(
      context: context,
      builder: (_) => SimpleBuyConfirmSheet(
        order: order,
        fiatAmount: fiatAmount,
        fiatCode: fiatCode,
        estimatedSats: estimatedSats,
        bondPercent: bondPercent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);
    final communityAsync = ref.watch(activeCommunityProfileProvider);
    final community = communityAsync.valueOrNull;
    final currency = community?.currency ?? 'USD';

    // Live exchange rate & Sats calculation
    final rateAsync = ref.watch(exchangeRateProvider(currency));
    final rate = rateAsync.valueOrNull;
    final double? parsedAmount = double.tryParse(_amountController.text.trim());
    final int? estimatedSats =
        (rate != null && rate > 0 && parsedAmount != null && parsedAmount > 0)
        ? (parsedAmount / rate * 100000000).round()
        : null;

    final paymentMethods =
        community != null && community.paymentMethods.isNotEmpty
        ? community.paymentMethods
        : const ['Transferencia', 'Efectivo', 'Móvil', 'Zelle'];

    if (_selectedMethod == null && paymentMethods.isNotEmpty) {
      _selectedMethod = paymentMethods.first;
    }

    final allOrders = ref.watch(orderBookProvider).valueOrNull ?? [];
    final allSellOrders = allOrders.where((o) {
      if (o.kind != 'sell') return false;
      if (o.fiatCode.toUpperCase() != currency.toUpperCase()) return false;
      if (_selectedMethod != null &&
          !o.paymentMethod.toLowerCase().contains(
            _selectedMethod!.toLowerCase(),
          )) {
        return false;
      }
      return true;
    }).toList();

    bool matchesAmount(OrderItem o) {
      if (parsedAmount == null || parsedAmount <= 0) return true;
      if (o.isRange) {
        final min = o.fiatAmountMin ?? 0.0;
        final max = o.fiatAmountMax ?? double.infinity;
        return parsedAmount >= min && parsedAmount <= max;
      } else {
        return o.fiatAmount == parsedAmount;
      }
    }

    final matchingSellOrders = allSellOrders.where(matchesAmount).toList();
    final displayedSellOrders =
        (_filterMatchingOnly && parsedAmount != null && parsedAmount > 0)
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
                Text(
                  '${SimpleL10n.referencePrice(context)}: ',
                  style: TextStyle(color: pal.textSecondary, fontSize: 12),
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
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
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
                  Text(
                    estimatedSats != null
                        ? '≈ $estimatedSats sats'
                        : (rateAsync.isLoading
                              ? SimpleL10n.calculatingRate(context)
                              : 'Recibirás Bitcoin al cambio del mercado'),
                    style: TextStyle(
                      color: pal.limeText,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: paymentMethods.map((method) {
            final isSelected = _selectedMethod == method;
            return ChoiceChip(
              label: Text(method),
              selected: isSelected,
              onSelected: (_) {
                setState(() => _selectedMethod = method);
              },
              selectedColor: pal.limeBorder,
              labelStyle: TextStyle(
                color: isSelected ? pal.limeText : pal.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 20),

        // Temporary guarantee notice
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
                      '${SimpleL10n.temporaryGuarantee(context)}: ~${community?.bondPercent ?? 3}%',
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
                parsedAmount != null &&
                parsedAmount > 0)
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
                  'Prueba con otro método de pago o publica una solicitud.',
                  style: TextStyle(color: pal.textTertiary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...displayedSellOrders.map((order) {
            final isRange = order.isRange;
            final double takeFiatAmount = isRange
                ? (parsedAmount ?? order.fiatAmountMin ?? 50.0)
                : (order.fiatAmount ?? 50.0);
            final int? orderEstimatedSats = (rate != null && rate > 0)
                ? (takeFiatAmount / rate * 100000000).round()
                : null;
            final bool amountMismatched =
                !isRange &&
                parsedAmount != null &&
                parsedAmount != order.fiatAmount;

            return _SellerOfferCard(
              order: order,
              isRange: isRange,
              takeFiatAmount: takeFiatAmount,
              orderEstimatedSats: orderEstimatedSats,
              amountMismatched: amountMismatched,
              currency: currency,
              pal: pal,
              onBuyPressed: () {
                _openConfirmSheet(
                  order: order,
                  fiatAmount: takeFiatAmount,
                  fiatCode: currency,
                  estimatedSats: orderEstimatedSats,
                  bondPercent: community?.bondPercent ?? 3,
                );
              },
            );
          }),
      ],
    );
  }
}

class _SellerOfferCard extends ConsumerWidget {
  const _SellerOfferCard({
    required this.order,
    required this.isRange,
    required this.takeFiatAmount,
    required this.orderEstimatedSats,
    required this.amountMismatched,
    required this.currency,
    required this.pal,
    required this.onBuyPressed,
  });

  final OrderItem order;
  final bool isRange;
  final double takeFiatAmount;
  final int? orderEstimatedSats;
  final bool amountMismatched;
  final String currency;
  final OrderBookPalette pal;
  final VoidCallback onBuyPressed;

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
                            Text(
                              ' (${SimpleL10n.counterpartyTrades(order.tradeCount, context)} · ${SimpleL10n.daysActive(order.daysActive, context)})',
                              style: TextStyle(
                                color: pal.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ] else ...[
                            Text(
                              '${SimpleL10n.newTrader(context)} · ${SimpleL10n.daysActive(order.daysActive, context)}',
                              style: TextStyle(
                                color: pal.textTertiary,
                                fontSize: 12,
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
                    if (isRange)
                      Text(
                        'Comprarás: ${takeFiatAmount.toInt()} ${order.fiatCode}',
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Pago: ${order.paymentMethod}',
                    style: TextStyle(color: pal.textSecondary, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onBuyPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: pal.limeText,
                    foregroundColor: Colors.black,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    isRange
                        ? '${SimpleL10n.buyButton(context)} ${takeFiatAmount.toInt()} $currency'
                        : '${SimpleL10n.buyButton(context)} ${order.fiatAmount?.toInt() ?? takeFiatAmount.toInt()} $currency',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
