import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';

/// Simple Mode: Help & Mediation Screen.
/// Provides friendly support information, FAQ on guarantees and escrow safety,
/// and direct access to community mediation assistance.
class SimpleHelpScreen extends ConsumerWidget {
  const SimpleHelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);
    final communityAsync = ref.watch(activeCommunityProfileProvider);
    final community = communityAsync.valueOrNull;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      children: [
        // Title
        Text(
          SimpleL10n.helpTitle(context),
          style: theme.textTheme.titleLarge?.copyWith(
            color: pal.textTitle,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Need Help Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: pal.surfaceCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: pal.limeBorder, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.support_agent_rounded,
                      color: pal.limeText, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      SimpleL10n.haveProblem(context),
                      style: TextStyle(
                        color: pal.textTitle,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                SimpleL10n.mediatorInfo(context),
                style: TextStyle(color: pal.textSecondary, fontSize: 13),
              ),
              if (community?.contact != null && community!.contact!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Contacto del operador: ${community.contact}',
                  style: TextStyle(
                    color: pal.limeText,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),

        // FAQ Section
        Text(
          SimpleL10n.faq(context),
          style: theme.textTheme.titleMedium?.copyWith(
            color: pal.textTitle,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // FAQ 1
        _buildFaqTile(
          context: context,
          question: SimpleL10n.faq1Q(context),
          answer: SimpleL10n.faq1A(context),
          pal: pal,
        ),
        const SizedBox(height: 10),

        // FAQ 2
        _buildFaqTile(
          context: context,
          question: SimpleL10n.faq2Q(context),
          answer: SimpleL10n.faq2A(context),
          pal: pal,
        ),
        const SizedBox(height: 10),

        // FAQ 3
        _buildFaqTile(
          context: context,
          question: '¿Qué hago si mi contraparte no responde?',
          answer:
              'Si pasan los tiempos estipulados y tu contraparte no responde, pulsa "Pedir Ayuda" dentro del detalle de la operación. El mediador se conectará a la sala de chat para verificar comprobantes y asistirte.',
          pal: pal,
        ),
      ],
    );
  }

  Widget _buildFaqTile({
    required BuildContext context,
    required String question,
    required String answer,
    required OrderBookPalette pal,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: pal.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.navBorder),
      ),
      child: ExpansionTile(
        title: Text(
          question,
          style: TextStyle(
            color: pal.textTitle,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        iconColor: pal.limeText,
        collapsedIconColor: pal.textSecondary,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            answer,
            style: TextStyle(
              color: pal.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
