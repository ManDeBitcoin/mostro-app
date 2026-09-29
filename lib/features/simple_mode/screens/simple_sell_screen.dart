import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';

/// Simple Mode: Sell Screen.
/// Guides the user to specify how much they want to sell,
/// how they want to receive payment, and publishes the offer cleanly.
class SimpleSellScreen extends ConsumerStatefulWidget {
  const SimpleSellScreen({super.key});

  @override
  ConsumerState<SimpleSellScreen> createState() => _SimpleSellScreenState();
}

class _SimpleSellScreenState extends ConsumerState<SimpleSellScreen> {
  final _amountController = TextEditingController(text: '100');
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
            // Route to AddOrderScreen with sell type
            context.push('${AppRoute.addOrder}?type=sell');
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
