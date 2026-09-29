import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/notification_bell.dart';
import 'package:mostro/shared/widgets/platform_aware_qr_scanner.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/community.dart' as community_api;
import 'package:mostro/src/rust/api/community.dart' show CommunityProfile;

/// Top bar for Simple Mode:
/// Displays active community badge (or General Market indicator),
/// mascot branding, and the notification bell.
class SimpleAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const SimpleAppBar({super.key});

  static const double _target = 48;
  static const double _glyphInset = (_target - 22) / 2;
  static const double _sideInset = 18;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  void _showCommunitySheet(
      BuildContext context, WidgetRef ref, CommunityProfile? profile) {
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: pal.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    profile != null ? Icons.verified_rounded : Icons.public_rounded,
                    color: profile != null ? pal.limeText : pal.textSecondary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.name ?? SimpleL10n.generalMarket(context),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: pal.textTitle,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          profile != null
                              ? SimpleL10n.communityVerified(context)
                              : SimpleL10n.generalMarket(context),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: pal.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: pal.textSecondary),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (profile != null) ...[
                if (profile.currency.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(
                          'Moneda:',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: pal.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(profile.currency),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                if (profile.paymentMethods.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: profile.paymentMethods
                          .map((m) => Chip(
                                label: Text(m),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await ref
                        .read(activeCommunityProfileProvider.notifier)
                        .clearProfile();
                  },
                  icon: const Icon(Icons.exit_to_app_rounded),
                  label: Text(SimpleL10n.generalMarket(context)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: pal.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  // Quick scan or paste QR dialog
                  _promptCommunityPayload(context, ref);
                },
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(SimpleL10n.scanCommunityQr(context)),
                style: FilledButton.styleFrom(
                  backgroundColor: pal.limeText,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _promptCommunityPayload(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final pal = OrderBookPalette.of(context);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: pal.surfaceCard,
        title: Text(
          SimpleL10n.scanCommunityQr(context),
          style: TextStyle(color: pal.textTitle),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pega el enlace o código de tu comunidad (mostro://community/... o JSON):',
              style: TextStyle(color: pal.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'mostro://community/...',
                hintStyle: TextStyle(color: pal.textTertiary),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(AppLocalizations.of(context).scanQrButtonLabel),
              onPressed: () async {
                final scanned = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (routeContext) => Scaffold(
                      backgroundColor: pal.bg,
                      appBar: redesignAppBar(
                        routeContext,
                        title: AppLocalizations.of(routeContext).scanQrCodeTitle,
                        onBack: () => Navigator.of(routeContext).pop(),
                      ),
                      body: PlatformAwareQrScanner(
                        hint: 'mostro://community/...',
                        onDetected: (value) => Navigator.of(routeContext).pop(value),
                      ),
                    ),
                  ),
                );
                if (scanned != null && context.mounted) {
                  controller.text = scanned;
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancelar', style: TextStyle(color: pal.textSecondary)),
          ),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              try {
                final parsed =
                    await community_api.parseCommunityPayload(input: text);
                await ref
                    .read(activeCommunityProfileProvider.notifier)
                    .applyProfile(parsed);
                if (context.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Comunidad ${parsed.name} activada')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al cargar comunidad: $e')),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: pal.limeText,
              foregroundColor: Colors.black,
            ),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = OrderBookPalette.of(context);
    final communityAsync = ref.watch(activeCommunityProfileProvider);
    final activeProfile = communityAsync.valueOrNull;
    final top = math.max(44.0, MediaQuery.paddingOf(context).top + 12);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _sideInset - _glyphInset,
        top - _glyphInset,
        _sideInset - _glyphInset,
        math.max(0, 12 - _glyphInset),
      ),
      child: SizedBox(
        height: _target,
        child: Row(
          children: [
            // Active community badge
            InkWell(
              onTap: () => _showCommunitySheet(context, ref, activeProfile),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: pal.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: activeProfile != null ? pal.limeBorder : pal.navBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      activeProfile != null
                          ? Icons.verified_rounded
                          : Icons.public_rounded,
                      size: 16,
                      color: activeProfile != null ? pal.limeText : pal.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        activeProfile?.name ?? SimpleL10n.generalMarket(context),
                        style: TextStyle(
                          color: pal.textTitle,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: pal.textSecondary,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            // Notification bell
            NotificationBell(),
          ],
        ),
      ),
    );
  }
}
