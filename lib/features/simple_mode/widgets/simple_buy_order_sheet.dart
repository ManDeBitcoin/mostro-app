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
import 'package:mostro/features/order/models/order_detail_rules.dart'
    show estimateSats;
import 'package:mostro/features/order/providers/bond_providers.dart'
    show bondEstimateProvider;
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart'
    show createOrderActionProvider, tradeRoleProvider;
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/models/payment_method_groups.dart'
    show methodsOf;
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/features/simple_mode/providers/payment_method_providers.dart';
import 'package:mostro/features/simple_mode/providers/simple_identity_provider.dart';
import 'package:mostro/features/simple_mode/widgets/payment_method_field.dart';
import 'package:mostro/features/simple_mode/widgets/simple_price_stepper.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show rawTradesProvider;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Modal bottom sheet that publishes the user's own buy order in Simple
/// Mode, for a buyer no offer on the Buy tab suits.
///
/// It asks for little the tab does not already have: the amount is the one
/// typed there, the currency the tab's, and the payment methods open with
/// the tab's ticks ([buyOrderTickedMethodsProvider]) — read against the
/// community's list, since an order names the community's methods and not
/// whatever an offer on the book was written with. What it adds is the
/// price against the market, and the order goes out as any Simple Mode
/// order does ([simpleBuyOrder]).
class SimpleBuyOrderSheet extends ConsumerStatefulWidget {
  const SimpleBuyOrderSheet({super.key, required this.fiatAmount});

  /// The whole amount typed on the Buy tab, or null while the field holds
  /// none an order can carry: the sheet then says so and publishes nothing.
  final int? fiatAmount;

  @override
  ConsumerState<SimpleBuyOrderSheet> createState() =>
      _SimpleBuyOrderSheetState();
}

class _SimpleBuyOrderSheetState extends ConsumerState<SimpleBuyOrderSheet> {
  /// The order's premium, a whole percent either side of the market.
  int _premium = 0;
  bool _submitting = false;
  String? _errorMessage;
  bool _askedNodeAgain = false;

  @override
  void initState() {
    super.initState();
    // As on the confirm sheets: a fetch of the node's info that came back
    // empty at a cold start is asked for once more where its deposit and
    // fee are about to be shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _askNodeAgainIfEmpty(ref.read(mostroNodeProvider));
    });
  }

  /// Asks for the node's info once more when [node] is an answer and it is
  /// empty; never while a fetch is in flight, and once per opening.
  void _askNodeAgainIfEmpty(AsyncValue<Object?> node) {
    if (_askedNodeAgain || node.isLoading || node.valueOrNull != null) return;
    _askedNodeAgain = true;
    ref.invalidate(mostroNodeProvider);
  }

  Future<void> _publish({
    required int fiatAmount,
    required String fiatCode,
    required List<String> paymentMethods,
  }) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    // Everything the answer will need, taken while the sheet is still up.
    // The order goes out whether or not it is when the node answers: a
    // sheet dragged away mid-flight is not a publish taken back, and its
    // `ref` and `context` are gone by then.
    final container = ProviderScope.containerOf(context, listen: false);
    final router = GoRouter.maybeOf(context);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final create = ref.read(createOrderActionProvider);

    try {
      final order = await create(
        simpleBuyOrder(
          fiatAmount: fiatAmount.toDouble(),
          fiatCode: fiatCode,
          paymentMethods: paymentMethods,
          premium: _premium.toDouble(),
        ),
      );
      container.invalidate(rawTradesProvider);
      container
          .read(tradeRoleProvider.notifier)
          .update((map) => {...map, order.id: true});

      // This sheet, and no other route: by its own handle, not "whatever
      // is on top".
      if (route != null && route.isActive) {
        route.isCurrent ? navigator.pop() : navigator.removeRoute(route);
      }
      // To the order either way. For a buyer who had put the sheet away
      // it is the only word that the order did go out.
      if (order.status == OrderStatus.waitingMakerBond) {
        router?.push(AppRoute.payBondPath(order.id));
      } else {
        router?.push(AppRoute.tradeDetailPath(order.id));
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
    final l10n = AppLocalizations.of(context);
    final myNym = ref.watch(myNymProvider).valueOrNull;
    ref.listen(mostroNodeProvider, (_, next) => _askNodeAgainIfEmpty(next));
    // The node's own policy and fee, never a default.
    final node = ref.watch(mostroNodeProvider).valueOrNull;
    // The tab's currency, read here and not handed over at the opening:
    // the card or the node's answer can arrive with the sheet up, and the
    // order has to go out in what the sheet shows.
    final fiatCode = ref.watch(simpleCurrencyProvider);
    final rate = ref.watch(exchangeRateProvider(fiatCode)).valueOrNull;

    final amount = widget.fiatAmount;
    // The sheet's own ticks, of the community's list — a seller's list —
    // and read live: the picker opened from here changes them under the
    // sheet. An order has to name its methods, so with none ticked — every
    // offer, on the tab — nothing can be published.
    final paymentMethods = tickedMethods(
      methodsOf(ref.watch(sellMethodGroupsProvider)),
      ref.watch(buyOrderTickedMethodsProvider),
    );

    // For display: the order carries no sats, the node prices it when a
    // seller takes it.
    final int? sats =
        amount == null
            ? null
            : estimateSats(
              fiat: amount.toDouble(),
              rate: rate,
              premium: _premium.toDouble(),
            );
    final feeShare = tradeFeeShare(sats: sats, nodeFee: node?.fee);
    final bondFigure =
        makerBondApplies(policy: node?.bondPolicy, applyTo: node?.bondApplyTo)
            ? simpleBondFigure(
              estimateSats:
                  sats == null || sats <= 0
                      ? null
                      : ref.watch(bondEstimateProvider(sats)).valueOrNull,
              fraction: node?.bondAmountPct,
              locale: Localizations.localeOf(context).toString(),
            )
            : null;

    final String? missing =
        amount == null
            ? l10n.orderAmountMustBeWhole
            : paymentMethods.isEmpty
            ? l10n.simpleMethodsChooseOne
            : null;

    // While the order is on its way nothing here can be changed or put
    // away by a tap: what is on screen is what was sent. A drag still
    // closes a sheet, which `_publish` is written for.
    return PopScope(
      canPop: !_submitting,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Row(
                children: [
                  Icon(
                    Icons.arrow_downward_rounded,
                    color: pal.limeText,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.simpleBuyOrderTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: pal.textTitle,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: pal.textSecondary),
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
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
                      label: l10n.simpleBuyOrderAmount,
                      value: amount == null ? '—' : '$amount $fiatCode',
                      pal: pal,
                      isHighlight: true,
                    ),
                    const Divider(height: 20),
                    _buildRow(
                      label: SimpleL10n.youWillReceive(context),
                      // Net of the buyer's half of the fee when the node has
                      // said what it charges, as on the take's summary.
                      value:
                          sats != null
                              ? '~${sats - (feeShare ?? 0)} sats'
                              : amount == null
                              ? '—'
                              : SimpleL10n.calculatingRate(context),
                      pal: pal,
                      subtitle:
                          sats != null && feeShare == null
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

              const SizedBox(height: 12),

              // Off while the order is on its way: a step or a tick made
              // then would show a price or a method the order does not have,
              // and the picker would be the route the answer closes.
              AbsorbPointer(
                key: const ValueKey('simple-buy-order-inputs'),
                absorbing: _submitting,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SimplePriceStepper(
                      premium: _premium,
                      onStep:
                          (step) => setState(
                            () => _premium = steppedPremium(_premium, step),
                          ),
                      side: PriceSide.buyer,
                      rate: rate,
                      currency: fiatCode,
                    ),

                    const SizedBox(height: 16),

                    Text(
                      l10n.simpleBuyOrderMethods,
                      style: TextStyle(
                        color: pal.textTitle,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    PaymentMethodField(
                      groups: sellMethodGroupsProvider,
                      ticked: buyOrderTickedMethodsProvider,
                      placeholder: l10n.simpleMethodsChoose,
                      hint: l10n.simpleBuyOrderMethodsHint,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // What happens next, and when not to pay
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
                        l10n.simpleBuyOrderNotice,
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

              // Why the button below is off, or what the node answered.
              if (missing != null || _errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage ?? missing!,
                  style: TextStyle(
                    color:
                        _errorMessage != null ? Colors.redAccent : Colors.amber,
                    fontSize: _errorMessage != null ? 12 : 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 20),

              FilledButton(
                onPressed:
                    _submitting || amount == null || paymentMethods.isEmpty
                        ? null
                        : () => _publish(
                          fiatAmount: amount,
                          fiatCode: fiatCode,
                          paymentMethods: paymentMethods,
                        ),
                style: FilledButton.styleFrom(
                  backgroundColor: pal.limeText,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child:
                    _submitting
                        ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                        : Text(
                          l10n.simpleBuyOrderAction,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
              ),
            ],
          ),
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
