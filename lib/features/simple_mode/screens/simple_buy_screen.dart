import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';

/// Simple Mode: Amount-first Buy Screen.
/// Guides the user to:
/// 1. Enter an amount
/// 2. Choose payment method (filtered by community if active)
/// 3. Select seller with clear reputation, fee, and temporary guarantee
class SimpleBuyScreen extends ConsumerStatefulWidget {
  const SimpleBuyScreen({super.key});

  @override
  ConsumerState<SimpleBuyScreen> createState() => _SimpleBuyScreenState();
}

class _SimpleBuyScreenState extends ConsumerState<SimpleBuyScreen> {
  final _amountController = TextEditingController(text: '50');
  String? _selectedMethod;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);
    final communityAsync = ref.watch(activeCommunityProfileProvider);
    final community = communityAsync.valueOrNull;
    final currency = community?.currency ?? 'USD';

    final paymentMethods = community != null && community.paymentMethods.isNotEmpty
        ? community.paymentMethods
        : const ['Transferencia', 'Efectivo', 'Móvil', 'Zelle'];

    if (_selectedMethod == null && paymentMethods.isNotEmpty) {
      _selectedMethod = paymentMethods.first;
    }

    final book = ref.watch(orderBookProvider);
    final allOrders = book.valueOrNull ?? [];
    // Filter sell orders matching currency
    final sellOrders = allOrders.where((o) => o.kind == 'sell').toList();

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
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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

        const SizedBox(height: 24),

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
                      '${SimpleL10n.temporaryGuarantee(context)}: ~3%',
                      style: TextStyle(
                        color: pal.textTitle,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      SimpleL10n.temporaryGuaranteeTooltip(context),
                      style: TextStyle(
                        color: pal.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Sellers List
        Text(
          SimpleL10n.viewOffers(context),
          style: theme.textTheme.titleMedium?.copyWith(
            color: pal.textTitle,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        if (sellOrders.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: pal.surfaceCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.storefront_outlined, size: 40, color: pal.textTertiary),
                const SizedBox(height: 12),
                Text(
                  'No hay vendedores activos en este momento.',
                  style: TextStyle(color: pal.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Puedes publicar una solicitud o volver a intentarlo más tarde.',
                  style: TextStyle(color: pal.textTertiary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...sellOrders.map((order) {
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
                      children: [
                        CircleAvatar(
                          backgroundColor: pal.navBorder,
                          radius: 16,
                          child: Icon(Icons.person, size: 18, color: pal.limeText),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vendedor verificado',
                                style: TextStyle(
                                  color: pal.textTitle,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded,
                                      color: Colors.amber, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    '4.9 (43 operaciones)',
                                    style: TextStyle(
                                      color: pal.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${order.fiatAmount} ${order.fiatCode}',
                          style: TextStyle(
                            color: pal.limeText,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pago: ${order.paymentMethod}',
                          style: TextStyle(color: pal.textSecondary, fontSize: 13),
                        ),
                        FilledButton(
                          onPressed: () {
                            context.push(AppRoute.takeSellPath(order.id));
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: pal.limeText,
                            foregroundColor: Colors.black,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(
                            SimpleL10n.buyButton(context),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
