import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/models/create_order_rules.dart'
    show makerBondApplies;
import 'package:mostro/features/order/models/invoice_rules.dart'
    show tradeFeeShare;
import 'package:mostro/features/order/providers/bond_providers.dart'
    show bondEstimateProvider;
import 'package:mostro/features/order/providers/trade_state_provider.dart'
    show createOrderActionProvider;
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/features/simple_mode/providers/simple_identity_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show refreshTrades;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Modal bottom sheet for confirming a Sell order in Simple Mode.
/// Confirms the amount, estimated sats, receiving payment method & details,
/// the deposit the node asks of makers (when it asks one), and publishes the
/// offer to the Mostro node.
class SimpleSellConfirmSheet extends ConsumerStatefulWidget {
  const SimpleSellConfirmSheet({
    super.key,
    required this.fiatAmount,
    required this.fiatCode,
    required this.paymentMethods,
    required this.paymentDetails,
    this.premium = 0.0,
    this.estimatedSats,
  });

  final double fiatAmount;
  final String fiatCode;

  /// Every method the seller ticked, at least one.
  final List<String> paymentMethods;
  final String paymentDetails;
  final double premium;

  /// For display only: the order is published at market price and the node
  /// fixes the sats when it is taken.
  final int? estimatedSats;

  @override
  ConsumerState<SimpleSellConfirmSheet> createState() =>
      _SimpleSellConfirmSheetState();
}

class _SimpleSellConfirmSheetState
    extends ConsumerState<SimpleSellConfirmSheet> {
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

  Future<void> _confirmAndPublish() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final params = simpleSellOrder(
        fiatAmount: widget.fiatAmount,
        fiatCode: widget.fiatCode,
        paymentMethods: widget.paymentMethods,
        premium: widget.premium,
      );

      final order = await ref.read(createOrderActionProvider)(params);
      refreshTrades(ref);

      if (!mounted) return;
      Navigator.of(context).pop(); // Close sheet

      if (order.status == OrderStatus.waitingMakerBond) {
        context.push(AppRoute.payBondPath(order.id));
      } else {
        context.push(AppRoute.tradeDetailPath(order.id));
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
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);
    final myNym = ref.watch(myNymProvider).valueOrNull;
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
        makerBondApplies(policy: node?.bondPolicy, applyTo: node?.bondApplyTo)
        ? simpleBondFigure(
            estimateSats: sats == null || sats <= 0
                ? null
                : ref.watch(bondEstimateProvider(sats)).valueOrNull,
            fraction: node?.bondAmountPct,
            locale: Localizations.localeOf(context).toString(),
          )
        : null;

    return SafeArea(
      // Scrolls: the methods and the details run to as many lines as they
      // need, and on a short screen the summary is taller than the sheet.
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Row(
              children: [
                Icon(Icons.arrow_upward_rounded, color: pal.limeText, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Confirma tu oferta de venta',
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
                  if (myNym != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          SimpleL10n.publishingAs(context),
                          style: TextStyle(
                            color: pal.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        Row(
                          children: [
                            NymAvatar(
                              iconIndex: myNym.iconIndex,
                              colorHue: myNym.colorHue,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              myNym.pseudonym,
                              style: TextStyle(
                                color: pal.limeText,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                  ],
                  _buildRow(
                    label: 'Vas a vender',
                    value:
                        '${widget.fiatAmount.toStringAsFixed(0)} ${widget.fiatCode}',
                    pal: pal,
                    isHighlight: true,
                  ),
                  const Divider(height: 20),
                  _buildRow(
                    label: 'Sats equivalentes',
                    value: widget.estimatedSats != null
                        ? '~${widget.estimatedSats} sats'
                        : SimpleL10n.calculatingRate(context),
                    pal: pal,
                  ),
                  if (feeShare != null) ...[
                    const Divider(height: 20),
                    _buildRow(
                      label: l10n.simpleCommunityFee,
                      value: '≈ $feeShare sats',
                      pal: pal,
                      subtitle: l10n.simpleFeeAddedToSats,
                    ),
                  ],
                  const Divider(height: 20),
                  _buildRow(
                    label: 'Prima / Margen',
                    value: widget.premium == 0
                        ? SimpleL10n.atMarketPrice(context)
                        : '+${widget.premium.toStringAsFixed(1)}%',
                    pal: pal,
                  ),
                  const Divider(height: 20),
                  _buildRow(
                    label: l10n.simpleSummaryMethods(
                      widget.paymentMethods.length,
                    ),
                    // One to a line: run together, a name breaks across
                    // two lines and reads as two methods.
                    value: widget.paymentMethods.join('\n'),
                    pal: pal,
                  ),
                  if (widget.paymentDetails.isNotEmpty) ...[
                    const Divider(height: 20),
                    _buildRow(
                      label: 'Datos de cobro',
                      value: widget.paymentDetails,
                      pal: pal,
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
                  Icon(Icons.shield_outlined, color: pal.limeText, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      SimpleL10n.safetyNoticeSell(context),
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
              onPressed: _submitting ? null : _confirmAndPublish,
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
                      SimpleL10n.confirmAndPublish(context),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: pal.textSecondary, fontSize: 13),
            ),
            const SizedBox(width: 16),
            // What is left of the row, and as many lines as it takes: a
            // list of payment methods does not fit beside its label, and a
            // value that is not allowed to wrap runs off the sheet.
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: isHighlight ? pal.limeText : pal.textTitle,
                  fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
                  fontSize: isHighlight ? 15 : 13,
                ),
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
