import 'package:flutter/material.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

enum MilestoneState { completed, current, upcoming }

/// Vertical progress tracker displaying human-centered milestones for a trade.
/// Hides internal Nostr protocol wire states behind reassuring real-world steps.
class SimpleTradeTimeline extends StatelessWidget {
  const SimpleTradeTimeline({
    super.key,
    required this.status,
    required this.isBuyer,
    this.isDisputed = false,
    this.showBond = false,
  });

  final OrderStatus status;
  final bool isBuyer;
  final bool isDisputed;

  /// Whether this trade has a deposit step at all: the node bonds trades, or
  /// the trade is waiting on one. Without it the milestone is left out
  /// rather than shown as done.
  final bool showBond;

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);

    // Calculate milestone states based on OrderStatus
    final isBondPaid = status != OrderStatus.waitingMakerBond &&
        status != OrderStatus.waitingTakerBond;

    // Not `inProgress`: that is the public book saying the order was taken,
    // which it says from the take until the trade ends. Whether the seller
    // has locked the sats only the node's private messages tell (#203).
    final isEscrowFunded = status == OrderStatus.active ||
        status == OrderStatus.fiatSent ||
        status == OrderStatus.success ||
        status == OrderStatus.settledHoldInvoice ||
        status == OrderStatus.dispute;

    final isFiatSent = status == OrderStatus.fiatSent ||
        status == OrderStatus.success ||
        status == OrderStatus.settledHoldInvoice;

    final isSuccess =
        status == OrderStatus.success || status == OrderStatus.settledHoldInvoice;

    // An order of ours nobody has taken: on the book (`pending`), or one
    // step short of it while the maker's deposit is unpaid. Nothing has
    // been accepted, and nothing after the take has begun.
    final isUntaken = status == OrderStatus.pending ||
        status == OrderStatus.waitingMakerBond;

    // Milestone 1: Accepted
    const m1 = MilestoneState.completed;

    // Milestone 2: Bond locked
    final m2 = isBondPaid ? MilestoneState.completed : MilestoneState.current;

    // Milestone 3: Escrow secured
    final m3 = isEscrowFunded
        ? MilestoneState.completed
        : (!isUntaken && (!showBond || isBondPaid)
              ? MilestoneState.current
              : MilestoneState.upcoming);

    // Milestone 4: Fiat transfer
    final m4 = isFiatSent
        ? MilestoneState.completed
        : (isEscrowFunded ? MilestoneState.current : MilestoneState.upcoming);

    // Milestone 5: Verification & confirmation
    final m5 = isSuccess
        ? MilestoneState.completed
        : (isFiatSent ? MilestoneState.current : MilestoneState.upcoming);

    // Milestone 6: Completed
    final m6 = isSuccess ? MilestoneState.completed : MilestoneState.upcoming;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: pal.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pal.navBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isUntaken) ...[
            // A maker's deposit comes before the order is on the book, so
            // here it is the first step and the wait for a taker the next.
            if (showBond)
              _buildMilestoneRow(
                title: SimpleL10n.guaranteeLocked(context),
                state: m2,
                pal: pal,
                isFirst: true,
              ),
            _buildMilestoneRow(
              title: AppLocalizations.of(context).simpleOfferWaitingTaker,
              state: status == OrderStatus.pending
                  ? MilestoneState.current
                  : MilestoneState.upcoming,
              pal: pal,
              isFirst: !showBond,
            ),
          ] else ...[
            _buildMilestoneRow(
              title: SimpleL10n.tradeAccepted(context),
              state: m1,
              pal: pal,
              isFirst: true,
            ),
            if (showBond)
              _buildMilestoneRow(
                title: SimpleL10n.guaranteeLocked(context),
                state: m2,
                pal: pal,
              ),
          ],
          _buildMilestoneRow(
            title: SimpleL10n.bitcoinSecured(context),
            state: m3,
            pal: pal,
          ),
          _buildMilestoneRow(
            title: isBuyer
                ? SimpleL10n.sendFiatStep(context)
                : 'Esperando transferencia del comprador',
            state: m4,
            pal: pal,
          ),
          _buildMilestoneRow(
            title: isBuyer
                ? SimpleL10n.waitingFiatConfirmation(context)
                : 'Verifica tu cuenta y confirma',
            state: m5,
            pal: pal,
          ),
          _buildMilestoneRow(
            title: isBuyer
                ? SimpleL10n.bitcoinReceived(context)
                : SimpleL10n.tradeCompleted(context),
            state: m6,
            pal: pal,
            isLast: !isDisputed,
          ),
          if (isDisputed) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: pal.surfaceNav,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orangeAccent, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.support_agent_rounded,
                          color: Colors.orangeAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'En mediación comunitaria',
                        style: TextStyle(
                          color: pal.textTitle,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildMediationStep(
                    label: SimpleL10n.mediationCaseReceived(context),
                    active: true,
                    pal: pal,
                  ),
                  _buildMediationStep(
                    label: SimpleL10n.mediatorAssigned(context),
                    active: true,
                    pal: pal,
                  ),
                  _buildMediationStep(
                    label: SimpleL10n.waitingMediationResolution(context),
                    active: false,
                    pal: pal,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMediationStep({
    required String label,
    required bool active,
    required OrderBookPalette pal,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 14,
            color: active ? Colors.orangeAccent : pal.textTertiary,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: active ? pal.textTitle : pal.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneRow({
    required String title,
    required MilestoneState state,
    required OrderBookPalette pal,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final color = switch (state) {
      MilestoneState.completed => pal.limeText,
      MilestoneState.current => Colors.amber,
      MilestoneState.upcoming => pal.textTertiary,
    };

    final icon = switch (state) {
      MilestoneState.completed => Icons.check_circle_rounded,
      MilestoneState.current => Icons.play_arrow_rounded,
      MilestoneState.upcoming => Icons.radio_button_unchecked,
    };

    // As tall as its title: one that takes two lines pushes the next step
    // down, and the line between the two icons grows with it.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(icon, size: 20, color: color),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    constraints: const BoxConstraints(minHeight: 24),
                    color: state == MilestoneState.completed
                        ? pal.limeText.withValues(alpha: 0.5)
                        : pal.navBorder,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 1, bottom: isLast ? 0 : 8),
              child: Text(
                title,
                style: TextStyle(
                  color: state == MilestoneState.upcoming
                      ? pal.textTertiary
                      : pal.textTitle,
                  fontWeight: state == MilestoneState.current
                      ? FontWeight.bold
                      : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
