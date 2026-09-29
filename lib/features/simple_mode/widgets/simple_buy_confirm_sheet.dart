import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show refreshTrades;
import 'package:mostro/src/rust/api/types.dart';

/// Modal bottom sheet for confirming a Buy order in Simple Mode.
/// Presents clear amounts, estimated sats, refundable temporary guarantee,
/// safety checkpoints, and dispatches the taker order.
class SimpleBuyConfirmSheet extends ConsumerStatefulWidget {
  const SimpleBuyConfirmSheet({
    super.key,
    required this.order,
    required this.fiatAmount,
    required this.fiatCode,
    this.estimatedSats,
    this.bondPercent = 3,
  });

  final OrderItem order;
  final double fiatAmount;
  final String fiatCode;
  final int? estimatedSats;
  final int bondPercent;

  @override
  ConsumerState<SimpleBuyConfirmSheet> createState() =>
      _SimpleBuyConfirmSheetState();
}

class _SimpleBuyConfirmSheetState extends ConsumerState<SimpleBuyConfirmSheet> {
  bool _submitting = false;
  String? _errorMessage;

  Future<void> _confirmAndBuy() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final trade = await ref.read(takeOrderActionProvider)(
        orderId: widget.order.id,
        role: TradeRole.buyer,
        fiatAmount: widget.fiatAmount,
      );

      refreshTrades(ref);
      ref.read(tradeRoleProvider.notifier).update(
            (map) => {...map, widget.order.id: true},
          );

      if (!mounted) return;
      Navigator.of(context).pop(); // Close bottom sheet

      // Navigate to trade detail or bond payment
      if (trade.order.status == OrderStatus.waitingTakerBond) {
        context.push(AppRoute.payBondPath(widget.order.id));
      } else {
        context.push(AppRoute.tradeDetailPath(widget.order.id));
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
                Icon(Icons.shield_rounded, color: pal.limeText, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    SimpleL10n.buyConfirmationTitle(context),
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
                    label: SimpleL10n.buySummary(context),
                    value: '${widget.fiatAmount.toStringAsFixed(2)} ${widget.fiatCode}',
                    pal: pal,
                    isHighlight: true,
                  ),
                  const Divider(height: 20),
                  _buildRow(
                    label: SimpleL10n.selectPaymentMethod(context),
                    value: widget.order.paymentMethod,
                    pal: pal,
                  ),
                  const Divider(height: 20),
                  _buildRow(
                    label: SimpleL10n.youWillReceive(context),
                    value: widget.estimatedSats != null
                        ? '~${widget.estimatedSats} sats'
                        : SimpleL10n.calculatingRate(context),
                    pal: pal,
                    isHighlight: true,
                  ),
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
                  Icon(Icons.info_outline_rounded,
                      color: pal.limeText, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      SimpleL10n.safetyNoticeBuy(context),
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
              onPressed: _submitting ? null : _confirmAndBuy,
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
                      SimpleL10n.confirmAndBuy(context),
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
