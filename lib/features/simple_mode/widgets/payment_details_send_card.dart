import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/simple_mode/models/payment_details_rules.dart';
import 'package:mostro/features/simple_mode/providers/payment_details_providers.dart';
import 'package:mostro/features/simple_mode/widgets/payment_details_editor.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';

/// The seller's side of handing over how to be paid, once the escrow is
/// locked: the details the device keeps for each of the order's methods,
/// and one button that sends them to the buyer over the trade's chat.
///
/// Nothing leaves without that tap — the seller reads what goes, and to a
/// buyer they can see has taken the trade. And "sent" is said only for a
/// message a relay took: the core answers for it, not this card.
///
/// [offerToSend] is whether a seller who has not sent them is asked to —
/// while the buyer is about to pay. Later in the trade the card only says
/// what was sent, and lets it be sent again.
class PaymentDetailsSendCard extends ConsumerStatefulWidget {
  const PaymentDetailsSendCard({
    super.key,
    required this.orderId,
    required this.paymentMethod,
    required this.offerToSend,
  });

  final String orderId;

  /// The order's methods, in the one string an order carries them in.
  final String paymentMethod;

  final bool offerToSend;

  @override
  ConsumerState<PaymentDetailsSendCard> createState() =>
      _PaymentDetailsSendCardState();
}

class _PaymentDetailsSendCardState
    extends ConsumerState<PaymentDetailsSendCard> {
  List<PaymentDetailsEntry> _entries = const [];
  bool _sending = false;
  String? _error;

  /// The seller asked to send them once more.
  bool _again = false;

  /// The send this card just made, shown until the core's own answer is
  /// read back.
  DateTime? _sentNow;

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final message = paymentDetailsMessage(
      header: l10n.simplePayDetailsMessageHeader,
      entries: _entries,
    );
    if (message == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final sent = await ref
          .read(paymentDetailsGatewayProvider)
          .send(widget.orderId, message);
      if (!mounted) return;
      // The conversation's preview, where the chat list reads it.
      ref
          .read(chatRoomsNotifierProvider.notifier)
          .foldIncoming(widget.orderId, sent);
      ref.invalidate(paymentDetailsSentAtProvider(widget.orderId));
      setState(() {
        _sending = false;
        _again = false;
        _sentNow = DateTime.fromMillisecondsSinceEpoch(
          platformInt64ToInt(sent.createdAt) * 1000,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = localizedDaemonError(
          l10n,
          e,
          fallback: l10n.simplePayDetailsSendFailed,
        );
      });
    }
  }

  /// `14:32` today, `7 oct · 14:32` for another day.
  String _when(BuildContext context, DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final material = MaterialLocalizations.of(context);
    final time = material.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return sameDay ? time : '${material.formatShortMonthDay(local)} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final answer = ref.watch(paymentDetailsSentAtProvider(widget.orderId));
    // Not known yet whether they were sent: neither form is shown, rather
    // than one that turns into the other a frame later.
    if (answer.isLoading && !answer.hasValue && _sentNow == null) {
      return const SizedBox.shrink();
    }
    final sentAt = _sentNow ?? answer.valueOrNull;
    final editing = _again || (sentAt == null && widget.offerToSend);
    if (sentAt == null && !editing) return const SizedBox.shrink();

    final toSend = paymentDetailsToSend(_entries);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: pal.surfaceCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: sentAt == null ? pal.limeBorder : pal.navBorder,
            width: sentAt == null ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sentAt != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: pal.limeText,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.simplePayDetailsSentAt(_when(context, sentAt)),
                      style: TextStyle(
                        color: pal.textTitle,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              if (!editing)
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed:
                          () => context.push(
                            AppRoute.chatRoomPath(widget.orderId),
                          ),
                      style: TextButton.styleFrom(
                        foregroundColor: pal.limeText,
                      ),
                      child: Text(l10n.simplePayDetailsViewChat),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _again = true),
                      style: TextButton.styleFrom(
                        foregroundColor: pal.textSecondary,
                      ),
                      child: Text(l10n.simplePayDetailsSendAgain),
                    ),
                  ],
                ),
            ] else ...[
              Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: pal.limeText,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.simplePayDetailsSendTitle,
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
                l10n.simplePayDetailsSendBody,
                style: TextStyle(
                  color: pal.textSecondary,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
            if (editing) ...[
              const SizedBox(height: 14),
              PaymentDetailsEditor(
                methods: orderPaymentMethods(widget.paymentMethod),
                selectable: true,
                enabled: !_sending,
                fieldColor: pal.surfaceNav,
                onChanged: (entries) => setState(() => _entries = entries),
              ),
              const SizedBox(height: 12),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
                const SizedBox(height: 8),
              ] else if (toSend.isEmpty) ...[
                Text(
                  l10n.simplePayDetailsNothingToSend,
                  style: TextStyle(color: pal.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: toSend.isEmpty || _sending ? null : _send,
                icon:
                    _sending
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                        : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  sentAt == null
                      ? l10n.simplePayDetailsSendAction
                      : l10n.simplePayDetailsSendAgain,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: pal.limeText,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
