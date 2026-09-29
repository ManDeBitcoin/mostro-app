import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/src/rust/api/disputes.dart' as disputes_api;

/// Dialog for requesting community mediation in Simple Mode.
/// Replaces technical "Open dispute" with human-centered assistance request.
class SimpleRequestHelpDialog extends ConsumerStatefulWidget {
  const SimpleRequestHelpDialog({
    super.key,
    required this.orderId,
  });

  final String orderId;

  static Future<bool?> show(BuildContext context, String orderId) {
    return showMostroDialog<bool>(
      context: context,
      builder: (_) => SimpleRequestHelpDialog(orderId: orderId),
    );
  }

  @override
  ConsumerState<SimpleRequestHelpDialog> createState() =>
      _SimpleRequestHelpDialogState();
}

class _SimpleRequestHelpDialogState
    extends ConsumerState<SimpleRequestHelpDialog> {
  final _reasonController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitHelpRequest() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final dispute = await disputes_api.openDispute(tradeId: widget.orderId);
      final openedAt = platformInt64ToInt(dispute.openedAt);

      ref.read(disputeNotifierProvider.notifier).upsert(
            DisputeItem(
              id: dispute.id,
              tradeId: dispute.tradeId,
              status: DisputeStatus.open,
              initiatedByMe: true,
              openedAt: openedAt,
            ),
          );

      if (!mounted) return;
      Navigator.of(context).pop(true);
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

    return MostroDialog(
      icon: Icons.support_agent_rounded,
      title: SimpleL10n.haveProblem(context),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            SimpleL10n.mediatorInfo(context),
            style: TextStyle(color: pal.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text(
            SimpleL10n.explainProblem(context),
            style: TextStyle(
              color: pal.textTitle,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonController,
            maxLines: 3,
            style: TextStyle(color: pal.textTitle, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Ej. No he recibido el pago o no responde...',
              hintStyle: TextStyle(color: pal.textTertiary, fontSize: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: pal.navBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: pal.navBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: pal.limeBorder),
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
      primary: ModalAction(
        label: SimpleL10n.sendRequest(context),
        onPressed: _submitting ? null : _submitHelpRequest,
        busy: _submitting,
      ),
      secondary: ModalAction(
        label: 'Cancelar',
        onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
      ),
    );
  }
}
