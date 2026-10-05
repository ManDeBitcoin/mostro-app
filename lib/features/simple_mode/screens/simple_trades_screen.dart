import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/widgets/pwa_prompt_banner.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Simple Mode: Trades Screen.
/// Clean, humanized list of active and completed operations.
class SimpleTradesScreen extends ConsumerStatefulWidget {
  const SimpleTradesScreen({super.key});

  @override
  ConsumerState<SimpleTradesScreen> createState() => _SimpleTradesScreenState();
}

class _SimpleTradesScreenState extends ConsumerState<SimpleTradesScreen> {
  int _selectedTab = 0; // 0: Active, 1: Completed

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);
    final tradesAsync = ref.watch(tradeRowsProvider);

    return Column(
      children: [
        const PwaPromptBanner(),
        // Tab selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: Center(
                    child: Text(
                      SimpleL10n.activeTrades(context),
                      style: TextStyle(
                        fontWeight:
                            _selectedTab == 0 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  selected: _selectedTab == 0,
                  onSelected: (val) {
                    if (val) setState(() => _selectedTab = 0);
                  },
                  selectedColor: pal.limeBorder,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ChoiceChip(
                  label: Center(
                    child: Text(
                      SimpleL10n.completedTrades(context),
                      style: TextStyle(
                        fontWeight:
                            _selectedTab == 1 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  selected: _selectedTab == 1,
                  onSelected: (val) {
                    if (val) setState(() => _selectedTab = 1);
                  },
                  selectedColor: pal.limeBorder,
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: tradesAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: pal.limeText),
            ),
            error: (_, _) => Center(
              child: Text(
                AppLocalizations.of(context).tradesLoadError,
                style: TextStyle(color: pal.textSecondary),
              ),
            ),
            data: (allRows) {
              final activeRows = allRows
                  .where((r) => r.state.group != TradeGroup.closed)
                  .toList();
              final closedRows = allRows
                  .where((r) => r.state.group == TradeGroup.closed)
                  .toList();

              final currentRows = _selectedTab == 0 ? activeRows : closedRows;

              if (currentRows.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _selectedTab == 0
                              ? Icons.swap_horiz_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 48,
                          color: pal.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          SimpleL10n.noTrades(context),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: pal.textTitle,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          SimpleL10n.noTradesDesc(context),
                          style: TextStyle(color: pal.textSecondary, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                itemCount: currentRows.length,
                itemBuilder: (context, index) {
                  final row = currentRows[index];
                  final isBuy = !row.isSelling;
                  final title = isBuy ? 'Compra de Bitcoin' : 'Venta de Bitcoin';
                  final isActionNeeded =
                      row.state.group == TradeGroup.needsAction;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: pal.surfaceCard,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isActionNeeded ? pal.limeBorder : pal.navBorder,
                        width: isActionNeeded ? 1.5 : 1,
                      ),
                    ),
                    child: InkWell(
                      onTap: () {
                        context.push(AppRoute.tradeDetailPath(row.orderId));
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isBuy
                                          ? Icons.arrow_downward_rounded
                                          : Icons.arrow_upward_rounded,
                                      color:
                                          isBuy ? pal.limeText : Colors.orangeAccent,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      title,
                                      style: TextStyle(
                                        color: pal.textTitle,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                                if (isActionNeeded)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: pal.limeBorder,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Tu turno',
                                      style: TextStyle(
                                        color: pal.limeText,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${row.fiatAmount ?? '—'} ${row.fiatCode}',
                                  style: TextStyle(
                                    color: pal.limeText,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                if (row.amountSats != null && row.amountSats! > 0)
                                  Text(
                                    '${row.amountSats} sats',
                                    style: TextStyle(
                                      color: pal.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Método: ${row.paymentMethod}',
                                  style: TextStyle(
                                    color: pal.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                if (row.peerHandle != null)
                                  Text(
                                    'Con: ${row.peerHandle}',
                                    style: TextStyle(
                                      color: pal.textTertiary,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
