import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart'
    show incomingMessageProvider;
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/messages.dart' as messages_api;
import 'package:mostro/src/rust/api/payment_details.dart' as payment_details_api;
import 'package:mostro/src/rust/api/types.dart' show ChatMessage, MessageType;

/// The Rust calls behind the seller's payment details, in one place a test
/// can replace.
///
/// Rust keeps the details — per payment method, with the identity — and
/// decides whether they may leave: only from the seller, only while the
/// escrow is locked, and "sent" only once a relay took the message. Dart
/// shows fields and composes the text.
class PaymentDetailsGateway {
  const PaymentDetailsGateway();

  /// What the device keeps for each of [methods], in their order; an empty
  /// text where it keeps nothing.
  Future<List<payment_details_api.PaymentDetails>> detailsFor(
    List<String> methods,
  ) async => payment_details_api.paymentDetailsFor(methods: methods);

  /// Keeps [details] for [method] in place of what was kept; empty forgets
  /// the method.
  Future<void> save(String method, String details) async =>
      payment_details_api.savePaymentDetails(method: method, details: details);

  /// Sends [content] to the buyer of [orderId] over the trade's chat.
  ///
  /// Fails with the markers of `send_payment_details`, worded by
  /// `localizedDaemonError`.
  Future<ChatMessage> send(String orderId, String content) async =>
      payment_details_api.sendPaymentDetails(orderId: orderId, content: content);

  /// When the details of [orderId] were sent from this device, or null.
  Future<DateTime?> sentAt(String orderId) async {
    final at = await payment_details_api.paymentDetailsSentAt(orderId: orderId);
    return at == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(platformInt64ToInt(at) * 1000);
  }
}

final paymentDetailsGatewayProvider = Provider<PaymentDetailsGateway>(
  (_) => const PaymentDetailsGateway(),
);

/// Whose details the fields on screen are showing.
///
/// The Sell tab stays mounted under whatever is pushed over Simple Mode —
/// the Account screen included — so its fields outlive an identity swap
/// unless something tells them. `resetIdentityScopedState` invalidates
/// this, and the fields that watch it start over from what the new identity
/// keeps: nothing.
final paymentDetailsOwnerProvider = Provider<Object>((_) => Object());

/// When the payment details of an order were sent from this device, or null
/// if they never were. Identity-scoped: `resetIdentityScopedState`
/// invalidates it.
final paymentDetailsSentAtProvider = FutureProvider.autoDispose
    .family<DateTime?, String>(
      (ref, orderId) => ref.watch(paymentDetailsGatewayProvider).sentAt(orderId),
    );

/// How many messages of the counterparty in an order's chat are unread:
/// what tells a buyer, without opening the chat, that the seller wrote —
/// their payment details arrive there.
///
/// Read again whenever a message arrives for the order. Whoever comes back
/// from the chat invalidates it: reading the room marks its messages read.
final unreadFromPeerProvider = FutureProvider.autoDispose.family<int, String>((
  ref,
  orderId,
) async {
  ref.watch(incomingMessageProvider(orderId));
  final messages = await messages_api.getMessages(tradeId: orderId);
  return messages
      .where(
        (message) =>
            message.messageType == MessageType.peer &&
            !message.isMine &&
            !message.isRead,
      )
      .length;
});
