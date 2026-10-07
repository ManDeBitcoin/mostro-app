import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/order/models/order_detail_rules.dart'
    show paymentMethodsSummary;
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/models/payment_details_rules.dart';
import 'package:mostro/features/simple_mode/providers/payment_details_providers.dart';
import 'package:mostro/features/simple_mode/widgets/payment_details_send_card.dart';
import 'package:mostro/features/simple_mode/widgets/simple_request_help_dialog.dart';
import 'package:mostro/features/simple_mode/widgets/simple_trade_timeline.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show rawTradesProvider;
import 'package:mostro/features/trades/widgets/release_confirmation_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart';

/// Simple Mode: Full Humanized Trade Detail View.
/// Displays progressive vertical milestones, payment instruction checkpoints,
/// primary action buttons ("YA PAGUÉ", "RECIBÍ EL DINERO"), direct counterparty chat,
/// and the community mediation ("PEDIR AYUDA") flow. For the user's own
/// order while nobody has taken it, the way to take it back off the book.
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
    this.hasBond = false,
  });

  final String orderId;
  final OrderStatus status;
  final bool isBuyer;
  final double? fiatAmount;
  final String fiatCode;
  final int? amountSats;
  final String paymentMethod;

  /// Whether this user locked, or must lock, a deposit for this trade: the
  /// trade row carries one. The node's policy alone would not do — with
  /// `bond_apply_to = take` the maker of the same trade locks nothing.
  final bool hasBond;

  @override
  ConsumerState<SimpleTradeDetailView> createState() =>
      _SimpleTradeDetailViewState();
}

class _SimpleTradeDetailViewState extends ConsumerState<SimpleTradeDetailView> {
  bool _markingPaid = false;
  bool _withdrawing = false;

  /// Withdraws the user's own order while nobody has taken it.
  ///
  /// Never in one tap, and never for an order that stopped being untaken
  /// while the question was up: a cancel sent on a trade that has just gone
  /// active is a request to the counterparty, not a withdrawal.
  Future<void> _handleWithdraw() async {
    if (_withdrawing) return;
    final confirmed = await showMostroSheet<bool>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return MostroSheet(
          title: l10n.simpleWithdrawTitle,
          // A maker's deposit is released by any cancel made before a
          // timeout (docs/ANTI_ABUSE_BOND.md): said where there is one.
          body: widget.hasBond
              ? l10n.simpleWithdrawBodyBond
              : l10n.simpleWithdrawBody,
          secondary: ModalAction(
            label: l10n.goBackButtonLabel,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          primary: ModalAction(
            label: l10n.simpleWithdrawConfirm,
            onPressed: () => Navigator.of(ctx).pop(true),
            tone: ModalTone.destructive,
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // The status as it reads now, not as it read when the button was
    // tapped: the view is pushed every change, under the sheet too.
    if (widget.status != OrderStatus.pending) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.simpleWithdrawTaken)));
      return;
    }

    // Taken before the wait, for an answer that finds the view gone.
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    final router = GoRouter.maybeOf(context);
    setState(() => _withdrawing = true);
    try {
      await ref.read(cancelOrderActionProvider)(widget.orderId);
      // The row of an order that never went active is not marked locally:
      // the node's `canceled` wipes it. Read the list again now.
      container.invalidate(rawTradesProvider);
      if (!mounted) return;
      // Sent, not done: the node's answer is what takes the order off the
      // book, a moment later.
      messenger.showSnackBar(SnackBar(content: Text(l10n.simpleWithdrawSent)));
      // Nothing is left to follow here.
      navigator.canPop() ? navigator.pop() : router?.go(AppRoute.home);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            localizedDaemonError(l10n, e, fallback: l10n.simpleWithdrawFailed),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

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
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localizedDaemonError(l10n, e, fallback: l10n.fiatSentFailed),
          ),
        ),
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
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localizedDaemonError(l10n, e, fallback: l10n.releaseFailed),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final isDisputed = widget.status == OrderStatus.dispute;
    // The user's own order with no counterparty yet: on the book, or one
    // step short of it while the maker's deposit is unpaid.
    final isUntaken =
        widget.status == OrderStatus.pending ||
        widget.status == OrderStatus.waitingMakerBond;
    final isSuccess =
        widget.status == OrderStatus.success ||
        widget.status == OrderStatus.settledHoldInvoice;

    final title = widget.isBuyer ? 'Compra de Bitcoin' : 'Venta de Bitcoin';
    // The order's methods as a list to read. An order carries them in one
    // string, comma-separated and — the user's own — with nothing after
    // the comma.
    final paymentMethods = paymentMethodsSummary(
      widget.paymentMethod,
    ).all.join(', ');
    final l10n = AppLocalizations.of(context);

    // The seller's payment details reach the buyer over the chat, sent from
    // the seller's card below; here only how many messages wait unread, so
    // a buyer told to pay knows the seller has written.
    final payingNow = widget.isBuyer && widget.status == OrderStatus.active;
    final unreadFromSeller =
        payingNow
            ? ref.watch(unreadFromPeerProvider(widget.orderId)).valueOrNull ?? 0
            : 0;
    final sellerMaySend = sellerMaySendPaymentDetails(
      isBuyer: widget.isBuyer,
      status: widget.status,
    );

    // The deposit step exists only for a trade that has one, or is waiting
    // on it right now.
    final showBond =
        widget.hasBond ||
        widget.status == OrderStatus.waitingMakerBond ||
        widget.status == OrderStatus.waitingTakerBond;

    final isChatAvailable =
        widget.status == OrderStatus.active ||
        widget.status == OrderStatus.fiatSent ||
        widget.status == OrderStatus.dispute;

    Future<void> onChatPressed() async {
      if (isChatAvailable) {
        await context.push(AppRoute.chatRoomPath(widget.orderId));
        // Reading the room marked its messages read.
        if (mounted) ref.invalidate(unreadFromPeerProvider(widget.orderId));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(SimpleL10n.chatWillUnlockWhenActive(context)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }

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
          IconButton(
            icon: Icon(
              Icons.chat_bubble_outline_rounded,
              color: isChatAvailable ? pal.limeText : pal.textSecondary,
            ),
            tooltip: isChatAvailable
                ? SimpleL10n.chatWithCounterpart(context)
                : SimpleL10n.chatWaitingPeer(context),
            onPressed: onChatPressed,
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.fiatAmount ?? '—'} ${widget.fiatCode}',
                        style: TextStyle(
                          color: pal.limeText,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
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
                ),
                OutlinedButton.icon(
                  onPressed: onChatPressed,
                  icon: const Icon(Icons.chat_rounded, size: 16),
                  label: Text(isChatAvailable ? 'Chat' : 'Chat (En espera)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isChatAvailable
                        ? pal.limeText
                        : pal.textSecondary,
                    side: BorderSide(
                      color: isChatAvailable ? pal.limeBorder : pal.navBorder,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 1. ACTION NEEDED: Waiting Buyer Invoice
          if (widget.status == OrderStatus.waitingBuyerInvoice) ...[
            if (widget.isBuyer) ...[
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
                        Icon(
                          Icons.receipt_long_rounded,
                          color: pal.limeText,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Factura Lightning requerida',
                            style: TextStyle(
                              color: pal.textTitle,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      SimpleL10n.uploadInvoiceDesc(context),
                      style: TextStyle(color: pal.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    context.push(AppRoute.addInvoicePath(widget.orderId)),
                icon: const Icon(Icons.receipt_long_rounded),
                label: Text(
                  SimpleL10n.uploadInvoiceAction(context),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
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
              const SizedBox(height: 16),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: pal.surfaceCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: pal.navBorder),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.amber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        SimpleL10n.waitingBuyerInvoiceDesc(context),
                        style: TextStyle(color: pal.textTitle, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],

          // 2. ACTION NEEDED: Waiting Escrow Payment (Seller hold invoice)
          if (widget.status == OrderStatus.waitingPayment) ...[
            if (!widget.isBuyer) ...[
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
                        Icon(Icons.bolt_rounded, color: pal.limeText, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Depósito de custodia requerido',
                            style: TextStyle(
                              color: pal.textTitle,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      SimpleL10n.payEscrowHoldDesc(context),
                      style: TextStyle(color: pal.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    context.push(AppRoute.payInvoicePath(widget.orderId)),
                icon: const Icon(Icons.bolt_rounded),
                label: Text(
                  SimpleL10n.payEscrowHoldAction(context),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
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
              const SizedBox(height: 16),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: pal.surfaceCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: pal.navBorder),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.amber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        SimpleL10n.waitingSellerEscrowDesc(context),
                        style: TextStyle(color: pal.textTitle, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],

          // 3. ACTION NEEDED: Waiting Security Bond
          if (widget.status == OrderStatus.waitingMakerBond ||
              widget.status == OrderStatus.waitingTakerBond) ...[
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
                      Icon(
                        Icons.lock_outline_rounded,
                        color: pal.limeText,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Depósito de fianza requerido',
                          style: TextStyle(
                            color: pal.textTitle,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    SimpleL10n.payBondDesc(context),
                    style: TextStyle(color: pal.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () =>
                  context.push(AppRoute.payBondPath(widget.orderId)),
              icon: const Icon(Icons.lock_outline_rounded),
              label: Text(
                SimpleL10n.payBondAction(context),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
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
            const SizedBox(height: 16),
          ],

          // Taken, real step unknown: the public book says `in-progress` from
          // the take until the trade ends, so it is not "pay now" (#203).
          if (widget.status == OrderStatus.inProgress) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: pal.surfaceCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: pal.navBorder),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context).simpleTakenWaitingNode,
                          style: TextStyle(
                            color: pal.textTitle,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (widget.isBuyer) ...[
                          const SizedBox(height: 4),
                          Text(
                            AppLocalizations.of(context).simpleDoNotPayYet,
                            style: TextStyle(
                              color: pal.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Payment Details Card (if Buyer and active)
          if (widget.isBuyer && widget.status == OrderStatus.active) ...[
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
                      Icon(
                        Icons.payment_rounded,
                        color: pal.limeText,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Envía ${widget.fiatAmount} ${widget.fiatCode}',
                          style: TextStyle(
                            color: pal.textTitle,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Método: $paymentMethods',
                    style: TextStyle(
                      color: pal.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // The account to pay into is not on the order — an order
                  // is public. The seller sends it over the chat.
                  Text(
                    l10n.simplePayDetailsFromSeller,
                    style: TextStyle(
                      color: pal.textTitle,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onChatPressed,
                        icon: const Icon(Icons.chat_rounded, size: 16),
                        label: Text(l10n.simplePayDetailsOpenChat),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: pal.limeText,
                          side: BorderSide(color: pal.limeBorder),
                        ),
                      ),
                      if (unreadFromSeller > 0)
                        Text(
                          l10n.simplePayDetailsNewMessages(unreadFromSeller),
                          style: TextStyle(
                            color: pal.limeText,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
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

          // The seller's payment details, while the buyer is about to pay:
          // the one thing the seller has to do at this step.
          if (sellerMaySend && widget.status == OrderStatus.active)
            PaymentDetailsSendCard(
              orderId: widget.orderId,
              paymentMethod: widget.paymentMethod,
              offerToSend: true,
            ),

          // Waiting fiat payment (if Seller and active)
          if (!widget.isBuyer && widget.status == OrderStatus.active) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: pal.surfaceCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: pal.navBorder),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      SimpleL10n.waitingFiatPaymentDesc(
                        widget.fiatAmount?.toString() ?? '—',
                        widget.fiatCode,
                        paymentMethods,
                        context,
                      ),
                      style: TextStyle(color: pal.textTitle, fontSize: 13),
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
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.amber,
                        size: 22,
                      ),
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

          // Buyer waiting release (if Buyer and fiatSent)
          if (widget.isBuyer && widget.status == OrderStatus.fiatSent) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: pal.surfaceCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: pal.limeBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    color: pal.limeText,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      SimpleL10n.waitingFiatConfirmationDesc(context),
                      style: TextStyle(color: pal.textTitle, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Past that step the card only says what was sent: a buyer who
          // marked the payment had an account to pay into.
          if (sellerMaySend && widget.status != OrderStatus.active)
            PaymentDetailsSendCard(
              orderId: widget.orderId,
              paymentMethod: widget.paymentMethod,
              offerToSend: false,
            ),

          // Progressive vertical timeline
          SimpleTradeTimeline(
            status: widget.status,
            isBuyer: widget.isBuyer,
            isDisputed: isDisputed,
            showBond: showBond,
          ),

          const SizedBox(height: 24),

          // Primary Context Actions
          if (widget.isBuyer && widget.status == OrderStatus.active) ...[
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
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
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
          ] else if (widget.status == OrderStatus.pending) ...[
            // The user's own order, on the book and untaken: the one thing
            // left to do with it is take it back. `pending` is shown for
            // nothing else (`shownTradeStatus`).
            OutlinedButton.icon(
              key: const ValueKey('simple-withdraw-offer'),
              onPressed: _withdrawing ? null : _handleWithdraw,
              icon: _withdrawing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.undo_rounded, size: 18),
              label: Text(
                l10n.simpleWithdrawOffer,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
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
                  Icon(
                    Icons.check_circle_rounded,
                    color: pal.limeText,
                    size: 40,
                  ),
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

          // Assistance section ("Pedir Ayuda"). Not for an order nobody has
          // taken: asking for help opens a dispute, and there is no one yet
          // to have one with — the node refuses it outside `active` and
          // `fiat-sent`. What the user can do with such an order is above.
          if (!isSuccess && !isDisputed && !isUntaken) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: pal.surfaceNav,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: pal.navBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.help_outline_rounded,
                    color: pal.textSecondary,
                    size: 20,
                  ),
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
                        context,
                        widget.orderId,
                      );
                      if (!context.mounted) return;
                      if (submitted == true) {
                        ref.invalidate(tradeStatusProvider(widget.orderId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Solicitud de ayuda enviada'),
                          ),
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
