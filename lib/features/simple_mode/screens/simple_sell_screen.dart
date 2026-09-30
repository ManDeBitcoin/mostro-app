import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';
import 'package:mostro/features/simple_mode/widgets/simple_sell_confirm_sheet.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';

/// Simple Mode: Amount-first Sell Wizard.
/// 1. Amount input with live Satoshi conversion
/// 2. Payment method selector (filtered by community if active)
/// 3. Recipient payment details input
/// 4. Explanatory stages of security escrow
/// 5. Bottom sheet confirmation summary before publishing offer
class SimpleSellScreen extends ConsumerStatefulWidget {
  const SimpleSellScreen({super.key});

  @override
  ConsumerState<SimpleSellScreen> createState() => _SimpleSellScreenState();
}

class _SimpleSellScreenState extends ConsumerState<SimpleSellScreen> {
  final _amountController = TextEditingController(text: '100');
  final _detailsController = TextEditingController();
  String? _selectedMethod;
  double _premium = 0.0;

  @override
  void dispose() {
    _amountController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  void _openConfirmSheet({
    required double fiatAmount,
    required String fiatCode,
    required String paymentMethod,
    required String paymentDetails,
    required double premium,
    required int? estimatedSats,
    required int bondPercent,
  }) {
    showMostroSheet(
      context: context,
      builder: (_) => SimpleSellConfirmSheet(
        fiatAmount: fiatAmount,
        fiatCode: fiatCode,
        paymentMethod: paymentMethod,
        paymentDetails: paymentDetails,
        premium: premium,
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

    // Live exchange rate & Satoshi estimation
    final rateAsync = ref.watch(exchangeRateProvider(currency));
    final rate = rateAsync.valueOrNull;
    final double? parsedAmount = double.tryParse(_amountController.text.trim());
    final double effectiveRate = (rate != null && rate > 0)
        ? rate * (1 + _premium / 100)
        : 0.0;
    final int? estimatedSats = (effectiveRate > 0 && parsedAmount != null && parsedAmount > 0)
        ? (parsedAmount / effectiveRate * 100000000).round()
        : null;

    final paymentMethods = community != null && community.paymentMethods.isNotEmpty
        ? community.paymentMethods
        : const ['Transferencia', 'Efectivo', 'Móvil', 'Zelle'];

    if (_selectedMethod == null && paymentMethods.isNotEmpty) {
      _selectedMethod = paymentMethods.first;
    }

    final allOrders = ref.watch(orderBookProvider).valueOrNull ?? [];
    final matchingBuyOrders = allOrders.where((o) {
      if (o.kind != 'buy') return false;
      if (o.fiatCode.toUpperCase() != currency.toUpperCase()) return false;
      if (o.isMine) return false;
      return true;
    }).toList();

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
                Icon(Icons.candlestick_chart_outlined, color: pal.limeText, size: 18),
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                      estimatedSats != null
                          ? '≈ $estimatedSats sats'
                          : (rateAsync.isLoading
                              ? SimpleL10n.calculatingRate(context)
                              : 'Cotización al cambio del mercado'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: pal.limeText,
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
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Premium / Margin selector
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
                children: [
                  Icon(Icons.percent_rounded, size: 18, color: pal.limeText),
                  const SizedBox(width: 8),
                  Text(
                    SimpleL10n.sellPremium(context),
                    style: TextStyle(
                      color: pal.textTitle,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _premium == 0 ? SimpleL10n.atMarketPrice(context) : '+${_premium.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: _premium > 0 ? pal.limeText : pal.textSecondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                SimpleL10n.sellPremiumTooltip(context),
                style: TextStyle(color: pal.textTertiary, fontSize: 11),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [0.0, 1.0, 2.0, 3.0, 5.0, 8.0, 10.0].map((val) {
                  final isSelected = _premium == val;
                  final label = val == 0.0 ? SimpleL10n.atMarketPrice(context) : '+${val.toInt()}%';
                  return ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _premium = val),
                    selectedColor: pal.limeBorder,
                    labelStyle: TextStyle(
                      color: isSelected ? pal.limeText : pal.textSecondary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),
              if (_premium > 0 && effectiveRate > 0) ...[
                const SizedBox(height: 10),
                Text(
                  '${SimpleL10n.effectivePrice(context)}: 1 BTC ≈ ${NumberFormat('#,##0.00', Localizations.localeOf(context).toString()).format(effectiveRate)} $currency',
                  style: TextStyle(
                    color: pal.limeText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
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

        // Payment Details Input
        Text(
          SimpleL10n.paymentDetailsPrompt(context),
          style: theme.textTheme.titleMedium?.copyWith(
            color: pal.textTitle,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: pal.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.navBorder),
          ),
          child: TextField(
            controller: _detailsController,
            style: TextStyle(color: pal.textTitle, fontSize: 14),
            decoration: InputDecoration(
              hintText: SimpleL10n.paymentDetailsHint(context),
              hintStyle: TextStyle(color: pal.textTertiary, fontSize: 13),
              border: InputBorder.none,
            ),
            maxLines: 2,
          ),
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

        // Publish Button
        FilledButton.icon(
          onPressed: () {
            _openConfirmSheet(
              fiatAmount: parsedAmount ?? 100.0,
              fiatCode: currency,
              paymentMethod: _selectedMethod ?? paymentMethods.first,
              paymentDetails: _detailsController.text.trim(),
              premium: _premium,
              estimatedSats: estimatedSats,
              bondPercent: community?.bondPercent ?? 3,
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
          ...matchingBuyOrders.map((order) => _BuyerOfferCard(
                order: order,
                currency: currency,
                pal: pal,
                onSellPressed: () =>
                    context.push(AppRoute.takeBuyPath(order.id)),
              )),
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
    final nym = ref.watch(peerNymProvider(order.creatorPubkey)).valueOrNull;

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
                              nym?.pseudonym ?? 'Comprador',
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
                                horizontal: 6, vertical: 2),
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
            // Premium tag
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
                                order.premium.toStringAsFixed(1), context)
                            : SimpleL10n.premiumBelow(
                                order.premium.toStringAsFixed(1), context)),
                    style: TextStyle(
                      fontSize: 11,
                      color: order.premium <= 0
                          ? pal.limeText
                          : Colors.orangeAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Paga con: ${order.paymentMethod}',
                    style: TextStyle(color: pal.textSecondary, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
