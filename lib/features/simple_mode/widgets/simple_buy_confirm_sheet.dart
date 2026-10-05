import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/models/create_order_rules.dart'
    show takerBondApplies;
import 'package:mostro/features/order/models/invoice_rules.dart'
    show tradeFeeShare;
import 'package:mostro/features/order/providers/bond_providers.dart'
    show bondEstimateProvider;
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show refreshTrades;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Modal bottom sheet for confirming a Buy order in Simple Mode.
/// Presents clear amounts, estimated sats, the deposit the node asks of
/// takers (when it asks one), safety checkpoints, and dispatches the take.
class SimpleBuyConfirmSheet extends ConsumerStatefulWidget {
  const SimpleBuyConfirmSheet({
    super.key,
    required this.order,
    required this.fiatAmount,
    required this.fiatCode,
    this.estimatedSats,
  });

  final OrderItem order;

  /// A whole amount: the order's own, or the one typed for a range order.
  final double fiatAmount;
  final String fiatCode;
  final int? estimatedSats;

  @override
  ConsumerState<SimpleBuyConfirmSheet> createState() =>
      _SimpleBuyConfirmSheetState();
}

class _SimpleBuyConfirmSheetState extends ConsumerState<SimpleBuyConfirmSheet> {
  bool _submitting = false;
  String? _errorMessage;
  bool _askedNodeAgain = false;

  @override
  void initState() {
    super.initState();
    // The node's info is fetched once and then kept by whichever tab is
    // mounted, so a fetch that came back empty at a cold start would leave
    // the deposit unannounced for the whole session. Ask again here, where
    // it is about to matter: for the answer already on hand now, and from
    // `build` for one that arrives while the sheet is open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _askNodeAgainIfEmpty(ref.read(mostroNodeProvider));
    });
  }

  /// Asks for the node's info once more when [node] is an answer and it is
  /// empty — nothing read, or a failed fetch.
  ///
  /// Not while a fetch is in flight: that is the question already asked, and
  /// restarting it would throw away an answer on its way. And once per
  /// opening, so a node that really announces nothing is not asked in a loop.
  void _askNodeAgainIfEmpty(AsyncValue<Object?> node) {
    if (_askedNodeAgain || node.isLoading || node.valueOrNull != null) return;
    _askedNodeAgain = true;
    ref.invalidate(mostroNodeProvider);
  }

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
      final l10n = AppLocalizations.of(context);
      setState(() {
        _submitting = false;
        _errorMessage = localizedDaemonError(
          l10n,
          e,
          fallback: l10n.orderRequestFailed,
          onTake: true,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);
    final nym = ref.watch(peerNymProvider(widget.order.creatorPubkey)).valueOrNull;
    // An answer that arrives empty while the sheet is open is asked for
    // once more, like one found empty at open (`initState`).
    ref.listen(mostroNodeProvider, (_, next) => _askNodeAgainIfEmpty(next));
    // The node's own policy, never a default: with bonds off, or before the
    // node has said, no deposit is shown.
    final node = ref.watch(mostroNodeProvider).valueOrNull;
    final sats = widget.estimatedSats;
    final l10n = AppLocalizations.of(context);
    // This side's half of the node's fee, when the node has said its fee.
    final feeShare = tradeFeeShare(sats: sats, nodeFee: node?.fee);
    final bondFigure =
        takerBondApplies(policy: node?.bondPolicy, applyTo: node?.bondApplyTo)
        ? simpleBondFigure(
            estimateSats: sats == null || sats <= 0
                ? null
                : ref.watch(bondEstimateProvider(sats)).valueOrNull,
            fraction: node?.bondAmountPct,
            locale: Localizations.localeOf(context).toString(),
          )
        : null;

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
            const SizedBox(height: 14),

            // Seller Profile Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pal.surfaceCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: pal.navBorder),
              ),
              child: Row(
                children: [
                  if (nym != null)
                    NymAvatar(
                      iconIndex: nym.iconIndex,
                      colorHue: nym.colorHue,
                      size: 38,
                    )
                  else
                    CircleAvatar(
                      backgroundColor: pal.navBorder,
                      radius: 19,
                      child: Icon(Icons.person, size: 20, color: pal.limeText),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                nym?.pseudonym ?? SimpleL10n.sellerProfile(context),
                                style: TextStyle(
                                  color: pal.textTitle,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: widget.order.premium <= 0
                                    ? pal.limeBorder.withValues(alpha: 0.15)
                                    : Colors.orangeAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.order.premium == 0
                                    ? SimpleL10n.marketRateZero(context)
                                    : (widget.order.premium > 0
                                        ? SimpleL10n.premiumAbove(widget.order.premium.toStringAsFixed(1), context)
                                        : SimpleL10n.premiumBelow(widget.order.premium.toStringAsFixed(1), context)),
                                style: TextStyle(
                                  color: widget.order.premium <= 0 ? pal.limeText : Colors.orangeAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 15,
                              color: widget.order.rating > 0 ? Colors.amber : pal.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            if (widget.order.tradeCount > 0) ...[
                              Text(
                                widget.order.rating.toStringAsFixed(1),
                                style: TextStyle(
                                  color: pal.textTitle,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                ' (${SimpleL10n.counterpartyTrades(widget.order.tradeCount, context)} · ${SimpleL10n.daysActive(widget.order.daysActive, context)})',
                                style: TextStyle(
                                  color: pal.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ] else ...[
                              Text(
                                '${SimpleL10n.newTrader(context)} · ${SimpleL10n.daysActive(widget.order.daysActive, context)}',
                                style: TextStyle(
                                  color: pal.textTertiary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

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
                    value: '${widget.fiatAmount.toStringAsFixed(0)} ${widget.fiatCode}',
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
                    // Net of the buyer's half of the fee when the node has
                    // said what it charges: that is what the invoice gets.
                    value: sats != null
                        ? '~${sats - (feeShare ?? 0)} sats'
                        : SimpleL10n.calculatingRate(context),
                    pal: pal,
                    isHighlight: true,
                    // With the fee unknown the figure is not net of it,
                    // and says so.
                    subtitle: sats != null && feeShare == null
                        ? l10n.simpleBeforeCommunityFee
                        : null,
                  ),
                  if (feeShare != null) ...[
                    const Divider(height: 20),
                    _buildRow(
                      label: l10n.simpleCommunityFee,
                      value: '≈ $feeShare sats',
                      pal: pal,
                      subtitle: l10n.simpleFeeTakenFromSats,
                    ),
                  ],
                  if (bondFigure != null) ...[
                    const Divider(height: 20),
                    _buildRow(
                      label: SimpleL10n.temporaryGuarantee(context),
                      value: bondFigure,
                      pal: pal,
                      subtitle: SimpleL10n.refundNotice(context),
                    ),
                  ],
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
