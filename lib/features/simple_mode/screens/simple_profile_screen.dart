import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/core/ui_mode.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';

/// Simple Mode: Profile Screen.
/// Clean, non-technical overview of user reputation, connected wallet,
/// active community, backup phrase access, and Advanced Mode toggle.
class SimpleProfileScreen extends ConsumerWidget {
  const SimpleProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);
    final communityAsync = ref.watch(activeCommunityProfileProvider);
    final community = communityAsync.valueOrNull;
    final nwcState = ref.watch(nwcProvider);
    final isWalletConnected = nwcState != null;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      children: [
        // User Identity Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: pal.surfaceCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: pal.navBorder),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: pal.navBorder,
                child: Icon(Icons.person, size: 32, color: pal.limeText),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mi Perfil',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: pal.textTitle,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '5.0',
                          style: TextStyle(
                            color: pal.limeText,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• Miembro activo',
                          style: TextStyle(
                            color: pal.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Community Section
        _buildSectionHeader(context, 'Comunidad', pal),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.surfaceCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: pal.navBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    community != null
                        ? Icons.verified_rounded
                        : Icons.public_rounded,
                    color: community != null ? pal.limeText : pal.textSecondary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      community?.name ?? SimpleL10n.generalMarket(context),
                      style: TextStyle(
                        color: pal.textTitle,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (community != null)
                    Chip(
                      label: Text(community.currency),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                community != null
                    ? 'Comunidad verificada. Todos los precios y métodos de pago se adaptan a esta región.'
                    : 'Estás operando en el mercado global abierto.',
                style: TextStyle(color: pal.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Lightning Wallet Section
        _buildSectionHeader(context, 'Billetera Lightning', pal),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.surfaceCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: pal.navBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    color: isWalletConnected ? pal.limeText : Colors.orangeAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isWalletConnected
                              ? SimpleL10n.walletConnected(context)
                              : SimpleL10n.walletDisconnected(context),
                          style: TextStyle(
                            color: pal.textTitle,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          isWalletConnected
                              ? 'Los pagos se autorizan automáticamente.'
                              : 'Conecta tu wallet para pagos automáticos rápidos.',
                          style: TextStyle(
                            color: pal.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push(AppRoute.walletSettings),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Text(
                  isWalletConnected ? 'Gestionar conexión' : 'Conectar con NWC',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: pal.limeText,
                  side: BorderSide(color: pal.limeBorder),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Recovery Words Section
        _buildSectionHeader(context, 'Seguridad y Respaldo', pal),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => context.push(AppRoute.keyManagement),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: pal.surfaceCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: pal.navBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.key_rounded, color: pal.limeText, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        SimpleL10n.recoveryWords(context),
                        style: TextStyle(
                          color: pal.textTitle,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        SimpleL10n.recoveryWordsDesc(context),
                        style: TextStyle(
                          color: pal.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: pal.textSecondary),
              ],
            ),
          ),
        ),

        const SizedBox(height: 28),

        // Advanced Mode Section (User Story 6)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: pal.surfaceNav,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: pal.navBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.terminal_rounded,
                          size: 20, color: pal.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        'Modo Avanzado',
                        style: TextStyle(
                          color: pal.textTitle,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: false,
                    onChanged: (val) {
                      if (val) {
                        ref
                            .read(uiModeProvider.notifier)
                            .setMode(UiMode.advanced);
                      }
                    },
                    activeThumbColor: pal.limeText,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                SimpleL10n.advancedModeDesc(context),
                style: TextStyle(color: pal.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSectionHeader(
      BuildContext context, String title, OrderBookPalette pal) {
    return Text(
      title,
      style: TextStyle(
        color: pal.textSecondary,
        fontWeight: FontWeight.w600,
        fontSize: 12,
        letterSpacing: 0.5,
      ),
    );
  }
}
