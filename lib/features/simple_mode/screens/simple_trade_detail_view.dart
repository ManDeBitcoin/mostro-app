import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/widgets/simple_request_help_dialog.dart';
import 'package:mostro/features/simple_mode/widgets/simple_trade_timeline.dart';
import 'package:mostro/features/trades/widgets/release_confirmation_sheet.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart';

/// Simple Mode: Full Humanized Trade Detail View.
/// Displays progressive vertical milestones, payment instruction checkpoints,
/// primary action buttons ("YA PAGUÉ", "RECIBÍ EL DINERO"), direct counterparty chat,
/// and the community mediation ("PEDIR AYUDA") flow.
class SimpleTradeDetailView extends ConsumerStatefulWidget {
  const SimpleTradeDetailView({
    super.key,
    required this.orderId,
    required this.status,
    required this.isBuyer,
    this.fiatAmount,
    this.fiatCode = 'USD',
    this.amountSats,
    this.paymentMethod = 'Transferencia',
    this.paymentDetails,
  });

  final String orderId;
  final OrderStatus status;
  final bool isBuyer;
  final double? fiatAmount;
  final String fiatCode;
  final int? amountSats;
  final String paymentMethod;
  final String? paymentDetails;

  @override
  ConsumerState<SimpleTradeDetailView> createState() =>
      _SimpleTradeDetailViewState();
}

class _SimpleTradeDetailViewState extends ConsumerState<SimpleTradeDetailView> {
  bool _markingPaid = false;

  Future<void> _handleFiatPaid() async {
    final confirmed = await showMostroDialog<bool>(
      context: context,
      builder: (ctx) => MostroDialog(
        title: 'Confirmar Pago',
        body: SimpleL10n.confirmPaymentSent(context),
        primary: ModalAction(
          label: 'Confirmar',
          onPressed: () => Navigator.pop(ctx, true),
        ),
        secondary: ModalAction(
          label: 'Cancelar',
          onPressed: () => Navigator.pop(ctx, false),
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _markingPaid = true);
    try {
      await orders_api.sendFiatSent(orderId: widget.orderId);
      ref.invalidate(tradeStatusProvider(widget.orderId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pago marcado como enviado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _markingPaid = false);
    }
  }

  Future<void> _handleReleaseMoney() async {
    final confirmed = await showReleaseConfirmationSheet(context);
    if (confirmed != true) return;

    try {
      await ref.read(releaseOrderActionProvider)(widget.orderId);
      ref.invalidate(tradeStatusProvider(widget.orderId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitcoin liberado con éxito')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al liberar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final isDisputed = widget.status == OrderStatus.dispute;
    final isSuccess = widget.status == OrderStatus.success ||
        widget.status == OrderStatus.settledHoldInvoice;

    final title = widget.isBuyer ? 'Compra de Bitcoin' : 'Venta de Bitcoin';

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: pal.textTitle),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: pal.textTitle,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          // Quick Chat Button
          IconButton(
            icon: Icon(Icons.chat_bubble_outline_rounded, color: pal.limeText),
            tooltip: SimpleL10n.chatWithCounterpart(context),
            onPressed: () {
              context.push(AppRoute.chatRoomPath(widget.orderId));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        children: [
          // Order summary banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: pal.surfaceCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: pal.navBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.fiatAmount ?? '—'} ${widget.fiatCode}',
                      style: TextStyle(
                        color: pal.limeText,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.amountSats != null && widget.amountSats! > 0)
                      Text(
                        '≈ ${widget.amountSats} sats',
                        style: TextStyle(
                          color: pal.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    context.push(AppRoute.chatRoomPath(widget.orderId));
                  },
                  icon: const Icon(Icons.chat_rounded, size: 16),
                  label: const Text('Chat'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: pal.limeText,
                    side: BorderSide(color: pal.limeBorder),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Payment Details Card (if Buyer and active)
          if (widget.isBuyer &&
              (widget.status == OrderStatus.active ||
                  widget.status == OrderStatus.inProgress)) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: pal.surfaceCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: pal.limeBorder, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.payment_rounded,
                          color: pal.limeText, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Envía ${widget.fiatAmount} ${widget.fiatCode}',
                        style: TextStyle(
                          color: pal.textTitle,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Método: ${widget.paymentMethod}',
                    style: TextStyle(
                        color: pal.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  if (widget.paymentDetails != null &&
                      widget.paymentDetails!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Datos de pago: ${widget.paymentDetails}',
                      style: TextStyle(color: pal.textTitle, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Checkpoint
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: pal.surfaceNav,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      SimpleL10n.safetyNoticeBuy(context),
                      style: TextStyle(
                        color: pal.textSecondary,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Seller Safety Notice (if Seller and fiatSent)
          if (!widget.isBuyer && widget.status == OrderStatus.fiatSent) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: pal.surfaceCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.amber, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.amber, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'El comprador indica que envió el dinero',
                          style: TextStyle(
                            color: pal.textTitle,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    SimpleL10n.safetyNoticeSell(context),
                    style: TextStyle(
                      color: pal.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Progressive vertical timeline
          SimpleTradeTimeline(
            status: widget.status,
            isBuyer: widget.isBuyer,
            isDisputed: isDisputed,
          ),

          const SizedBox(height: 24),

          // Primary Context Actions
          if (widget.isBuyer &&
              (widget.status == OrderStatus.active ||
                  widget.status == OrderStatus.inProgress)) ...[
            FilledButton(
              onPressed: _markingPaid ? null : _handleFiatPaid,
              style: FilledButton.styleFrom(
                backgroundColor: pal.limeText,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _markingPaid
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : Text(
                      SimpleL10n.iHavePaid(context),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
            const SizedBox(height: 16),
          ] else if (!widget.isBuyer &&
              widget.status == OrderStatus.fiatSent) ...[
            FilledButton(
              onPressed: _handleReleaseMoney,
              style: FilledButton.styleFrom(
                backgroundColor: pal.limeText,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                SimpleL10n.iReceivedMoney(context),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ] else if (isSuccess) ...[
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: pal.surfaceCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: pal.limeText, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    SimpleL10n.tradeCompleted(context),
                    style: TextStyle(
                      color: pal.textTitle,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Assistance section ("Pedir Ayuda")
          if (!isSuccess && !isDisputed) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: pal.surfaceNav,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: pal.navBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.help_outline_rounded,
                      color: pal.textSecondary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      SimpleL10n.haveProblem(context),
                      style: TextStyle(
                        color: pal.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final submitted = await SimpleRequestHelpDialog.show(
                          context, widget.orderId);
                      if (!context.mounted) return;
                      if (submitted == true) {
                        ref.invalidate(tradeStatusProvider(widget.orderId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Solicitud de ayuda enviada')),
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                    ),
                    child: Text(SimpleL10n.requestHelp(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}
