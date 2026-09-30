import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show refreshTrades;
import 'package:mostro/src/rust/api/orders.dart' as rust_orders;
import 'package:mostro/src/rust/api/types.dart';

/// Modal bottom sheet for confirming a Sell order in Simple Mode.
/// Confirms the amount, estimated sats, receiving payment method & details,
/// security guarantee, and publishes the offer to the Mostro node.
class SimpleSellConfirmSheet extends ConsumerStatefulWidget {
  const SimpleSellConfirmSheet({
    super.key,
    required this.fiatAmount,
    required this.fiatCode,
    required this.paymentMethod,
    required this.paymentDetails,
    this.premium = 0.0,
    this.estimatedSats,
    this.bondPercent = 3,
  });

  final double fiatAmount;
  final String fiatCode;
  final String paymentMethod;
  final String paymentDetails;
  final double premium;
  final int? estimatedSats;
  final int bondPercent;

  @override
  ConsumerState<SimpleSellConfirmSheet> createState() =>
      _SimpleSellConfirmSheetState();
}

class _SimpleSellConfirmSheetState extends ConsumerState<SimpleSellConfirmSheet> {
  bool _submitting = false;
  String? _errorMessage;

  Future<void> _confirmAndPublish() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final params = NewOrderParams(
        kind: OrderKind.sell,
        fiatAmount: widget.fiatAmount,
        fiatCode: widget.fiatCode,
        paymentMethod: widget.paymentMethod,
        premium: widget.premium,
        amountSats: widget.estimatedSats != null
            ? BigInt.from(widget.estimatedSats!)
            : null,
      );

      final order = await rust_orders.createOrder(params: params);
      refreshTrades(ref);

      if (!mounted) return;
      Navigator.of(context).pop(); // Close sheet

      if (order.status == OrderStatus.waitingMakerBond) {
        context.push(AppRoute.payBondPath(order.id));
      } else {
        context.push(AppRoute.myOrderPath(order.id));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Row(
              children: [
                Icon(Icons.arrow_upward_rounded,
                    color: pal.limeText, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Confirma tu oferta de venta',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: pal.textTitle,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: pal.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Summary Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: pal.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: pal.navBorder),
              ),
              child: Column(
                children: [
                  _buildRow(
                    label: 'Vas a vender',
                    value:
                        '${widget.fiatAmount.toStringAsFixed(2)} ${widget.fiatCode}',
                    pal: pal,
                    isHighlight: true,
                  ),
                  const Divider(height: 20),
                  _buildRow(
                    label: 'Sats equivalentes',
                    value: widget.estimatedSats != null
                        ? '~${widget.estimatedSats} sats'
                        : SimpleL10n.calculatingRate(context),
                    pal: pal,
                  ),
                  const Divider(height: 20),
                  _buildRow(
                    label: 'Prima / Margen',
                    value: widget.premium == 0
                        ? SimpleL10n.atMarketPrice(context)
                        : '+${widget.premium.toStringAsFixed(1)}%',
                    pal: pal,
                  ),
                  const Divider(height: 20),
                  _buildRow(
                    label: 'Método de pago',
                    value: widget.paymentMethod,
                    pal: pal,
                  ),
                  if (widget.paymentDetails.isNotEmpty) ...[
                    const Divider(height: 20),
                    _buildRow(
                      label: 'Datos de cobro',
                      value: widget.paymentDetails,
                      pal: pal,
                    ),
                  ],
                  const Divider(height: 20),
                  _buildRow(
                    label: SimpleL10n.temporaryGuarantee(context),
                    value: '${widget.bondPercent}% (Reembolsable)',
                    pal: pal,
                    subtitle: SimpleL10n.refundNotice(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Safety checkpoint notice
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pal.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: pal.limeBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined,
                      color: pal.limeText, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      SimpleL10n.safetyNoticeSell(context),
                      style: TextStyle(
                        color: pal.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 20),

            // Confirm Button
            FilledButton(
              onPressed: _submitting ? null : _confirmAndPublish,
              style: FilledButton.styleFrom(
                backgroundColor: pal.limeText,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      SimpleL10n.confirmAndPublish(context),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow({
    required String label,
    required String value,
    required OrderBookPalette pal,
    String? subtitle,
    bool isHighlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: pal.textSecondary,
                fontSize: 13,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: isHighlight ? pal.limeText : pal.textTitle,
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
                fontSize: isHighlight ? 15 : 13,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(color: pal.textTertiary, fontSize: 11),
          ),
        ],
      ],
    );
  }
}
