import 'dart:async';

import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/features/simple_mode/providers/payment_details_providers.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/payment_details.dart' show PaymentDetails;
import 'package:mostro/src/rust/api/types.dart' show ChatMessage, MessageType;

/// A device's kept payment details and its chat, without Rust: what a
/// screen reads, keeps and sends is recorded here.
class FakePaymentDetailsGateway implements PaymentDetailsGateway {
  FakePaymentDetailsGateway({Map<String, String> kept = const {}}) {
    kept.forEach(
      (method, details) => this.kept[paymentMethodKey(method)] = details,
    );
  }

  /// What the device keeps, by [paymentMethodKey].
  final kept = <String, String>{};

  /// Every save, in order: the method as it was named, and the text.
  final saves = <({String method, String details})>[];

  /// Every message that left, in order.
  final sent = <({String orderId, String content})>[];

  /// When each order's details were sent.
  final sentAtByOrder = <String, DateTime>{};

  /// What the next sends fail with, if anything.
  Object? sendError;

  /// When set, a read waits for it: an answer that arrives late.
  Completer<void>? holdReads;

  @override
  Future<List<PaymentDetails>> detailsFor(List<String> methods) async {
    await holdReads?.future;
    return [
      for (final method in methods)
        PaymentDetails(
          method: method,
          details: kept[paymentMethodKey(method)] ?? '',
        ),
    ];
  }

  @override
  Future<void> save(String method, String details) async {
    saves.add((method: method, details: details));
    final text = details.trim();
    if (text.isEmpty) {
      kept.remove(paymentMethodKey(method));
    } else {
      kept[paymentMethodKey(method)] = text;
    }
  }

  @override
  Future<ChatMessage> send(String orderId, String content) async {
    final error = sendError;
    if (error != null) throw error;
    sent.add((orderId: orderId, content: content));
    final at = DateTime(2026, 10, 7, 14, 32);
    sentAtByOrder[orderId] = at;
    return ChatMessage(
      id: 'sent-${sent.length}',
      tradeId: orderId,
      senderPubkey: 'me',
      content: content,
      messageType: MessageType.peer,
      isMine: true,
      isRead: true,
      hasAttachment: false,
      createdAt: intToPlatformInt64(at.millisecondsSinceEpoch ~/ 1000),
    );
  }

  @override
  Future<DateTime?> sentAt(String orderId) async => sentAtByOrder[orderId];
}
