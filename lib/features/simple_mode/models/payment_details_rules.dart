import 'package:flutter/foundation.dart';
import 'package:mostro/features/order/models/order_detail_rules.dart'
    show paymentMethodsSummary;
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart'
    show paymentMethodKey;
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

/// Pure rules of the seller's payment details in Simple Mode: what the
/// screens show, and the message the buyer reads. Keeping them, and deciding
/// whether they may leave the device, is the core's
/// (`rust/src/mostro/payment_details.rs`).

/// One payment method on a seller's screen, with what is written for it.
@immutable
class PaymentDetailsEntry {
  const PaymentDetailsEntry({
    required this.method,
    required this.details,
    this.included = true,
  });

  /// The method's name, as the order or the community's list writes it.
  final String method;

  /// What the seller wrote: account, holder, phone. Free text.
  final String details;

  /// Whether the seller left this method ticked for the message. Always
  /// true where there is nothing to tick (the Sell tab).
  final bool included;

  @override
  bool operator ==(Object other) =>
      other is PaymentDetailsEntry &&
      other.method == method &&
      other.details == details &&
      other.included == included;

  @override
  int get hashCode => Object.hash(method, details, included);
}

/// The methods of an order, from the one string it carries them in
/// (`A,B,C`), each once. Split as everywhere else in Simple Mode
/// ([paymentMethodsSummary]) and told apart as everywhere else
/// ([paymentMethodKey], which is also how the core keeps their details).
List<String> orderPaymentMethods(String paymentMethod) {
  final seen = <String>{};
  return [
    for (final method in paymentMethodsSummary(paymentMethod).all)
      if (seen.add(paymentMethodKey(method))) method,
  ];
}

/// Whether the seller is offered the card that sends their details.
///
/// The same rule the core refuses by (`may_send`): the seller, while the
/// escrow is locked. The public book's `in-progress` is not that — it says
/// taken, never locked (#203).
bool sellerMaySendPaymentDetails({
  required bool isBuyer,
  required OrderStatus status,
}) =>
    !isBuyer &&
    (status == OrderStatus.active ||
        status == OrderStatus.fiatSent ||
        status == OrderStatus.dispute);

/// Of [entries], the ones a message would carry: ticked, and with text.
List<PaymentDetailsEntry> paymentDetailsToSend(
  Iterable<PaymentDetailsEntry> entries,
) => [
  for (final entry in entries)
    if (entry.included && entry.details.trim().isNotEmpty)
      PaymentDetailsEntry(
        method: entry.method.trim(),
        details: entry.details.trim(),
      ),
];

/// The chat message that carries the seller's details to the buyer, or null
/// when [entries] leave nothing to send.
///
/// Plain text, a method to a block: any Mostro client shows a chat message
/// as it was written, so the buyer reads this whatever app they hold.
/// [header] is the first line, in the seller's language.
String? paymentDetailsMessage({
  required String header,
  required Iterable<PaymentDetailsEntry> entries,
}) {
  final sent = paymentDetailsToSend(entries);
  if (sent.isEmpty) return null;
  return [
    header.trim(),
    for (final entry in sent) '${entry.method}\n${entry.details}',
  ].join('\n\n');
}
