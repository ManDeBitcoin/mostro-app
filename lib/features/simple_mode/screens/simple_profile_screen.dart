import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/core/ui_mode.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/account/widgets/backup_trigger_sheet.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';
import 'package:mostro/features/notifications/services/pwa_service.dart';
import 'package:mostro/features/notifications/services/push_notification_service.dart';
import 'package:mostro/features/simple_mode/providers/simple_identity_provider.dart';
import 'package:mostro/features/simple_mode/widgets/a2hs_guide_modal.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';

/// Simple Mode: Profile Screen.
/// Clean, non-technical overview of user reputation, connected wallet,
/// active community, backup phrase access, and Advanced Mode toggle.
class SimpleProfileScreen extends ConsumerWidget {
  const SimpleProfileScreen({super.key});

  void _showEditLightningAddressDialog(
    BuildContext context,
    WidgetRef ref,
    String? currentAddress,
  ) {
    final controller = TextEditingController(text: currentAddress ?? '');
    String? errorText;

    showMostroDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => MostroDialog(
          title: 'Dirección Lightning',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Introduce tu dirección Lightning para recibir Bitcoin (ejemplo: usuario@walletofsatoshi.com):',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'alias@proveedor.com',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (errorText != null) {
                    setDialogState(() => errorText = null);
                  }
                },
              ),
            ],
          ),
          links: currentAddress != null
              ? [
                  ModalLink(
                    label: 'Eliminar dirección',
                    onPressed: () {
                      ref
                          .read(settingsProvider.notifier)
                          .setDefaultLightningAddress(null);
                      Navigator.pop(dialogCtx);
                    },
                  ),
                ]
              : const [],
          secondary: ModalAction(
            label: 'Cancelar',
            onPressed: () => Navigator.pop(dialogCtx),
          ),
          primary: ModalAction(
            label: 'Guardar',
            onPressed: () {
              final input = controller.text.trim();
              if (input.isEmpty) {
                ref
                    .read(settingsProvider.notifier)
                    .setDefaultLightningAddress(null);
                Navigator.pop(dialogCtx);
                return;
              }
              final parts = input.split('@');
              if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
                setDialogState(
                  () => errorText =
                      'Formato inválido (debe ser usuario@dominio.com)',
                );
                return;
              }
              ref
                  .read(settingsProvider.notifier)
                  .setDefaultLightningAddress(input);
              Navigator.pop(dialogCtx);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);
    final nwcState = ref.watch(nwcProvider);
    final isWalletConnected = nwcState != null;
    final settings = ref.watch(settingsProvider);
    final lightningAddress = settings.defaultLightningAddress;
    final isBackedUp = ref.watch(backupCompletedProvider);

    final nym = ref.watch(myNymProvider).valueOrNull;

    final pwa = PwaService.instance;
    final areNotifsGranted = pwa.areNotificationsGranted;

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
              if (nym != null)
                NymAvatar(
                  iconIndex: nym.iconIndex,
                  colorHue: nym.colorHue,
                  size: 56,
                )
              else
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
                      nym?.pseudonym ?? 'Mi Identidad Nostr',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: pal.textTitle,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Colors.amber,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Identidad P2P',
                          style: TextStyle(
                            color: pal.limeText,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• Modo Simple',
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

        // Lightning Address Section
        _buildSectionHeader(context, 'Dirección Lightning (lud16)', pal),
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
                    color: lightningAddress != null
                        ? pal.limeText
                        : Colors.orangeAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lightningAddress ?? 'Sin dirección configurada',
                          style: TextStyle(
                            color: pal.textTitle,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lightningAddress != null
                              ? 'Recibirás tus compras de Bitcoin directamente aquí sin crear facturas manuales.'
                              : 'Configura una dirección (ej. satoshi@walletofsatoshi.com) para recibir pagos automáticamente.',
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
                onPressed: () => _showEditLightningAddressDialog(
                  context,
                  ref,
                  lightningAddress,
                ),
                icon: Icon(
                  lightningAddress != null
                      ? Icons.edit_outlined
                      : Icons.add_rounded,
                  size: 18,
                ),
                label: Text(
                  lightningAddress != null
                      ? 'Modificar dirección'
                      : 'Configurar dirección',
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

        // Community Section
        _buildSectionHeader(context, 'Comunidad / Nodo Mostro', pal),
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
                  Icon(Icons.verified_rounded, color: pal.limeText, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      defaultMostroName,
                      style: TextStyle(
                        color: pal.textTitle,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                SimpleL10n.communityVerified(context),
                style: TextStyle(color: pal.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Lightning Wallet Section (NWC)
        _buildSectionHeader(context, 'Billetera Externa (NWC)', pal),
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
                    Icons.account_balance_wallet_outlined,
                    color: isWalletConnected ? pal.limeText : pal.textSecondary,
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
                              ? 'Los depósitos de garantía se autorizan automáticamente.'
                              : 'Conecta un nodo o billetera NWC para pagar depósitos al instante.',
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

        // Recovery Words Section (Point 7 of B)
        _buildSectionHeader(context, 'Seguridad y Respaldo (BIP-39)', pal),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.surfaceCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isBackedUp
                  ? pal.navBorder
                  : Colors.amber.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isBackedUp
                        ? Icons.verified_user_rounded
                        : Icons.warning_amber_rounded,
                    color: isBackedUp ? pal.limeText : Colors.amber,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isBackedUp
                              ? 'Copia de respaldo activa'
                              : '¡Respaldo pendiente!',
                          style: TextStyle(
                            color: pal.textTitle,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isBackedUp
                              ? 'Tus 12 palabras están protegidas. Puedes consultarlas o exportarlas.'
                              : 'Guarda tus 12 palabras secretas para proteger tus fondos y reputación.',
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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (isBackedUp) {
                          context.push(AppRoute.keyManagement);
                        } else {
                          showBackupTriggerSheet(context);
                        }
                      },
                      icon: const Icon(Icons.key_rounded, size: 18),
                      label: Text(
                        isBackedUp
                            ? 'Ver palabras secretas'
                            : 'Respaldar ahora',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isBackedUp
                            ? pal.textTitle
                            : Colors.amber,
                        side: BorderSide(
                          color: isBackedUp ? pal.navBorder : Colors.amber,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Notifications & PWA Section
        _buildSectionHeader(
          context,
          'Notificaciones y Acceso Rápido (PWA)',
          pal,
        ),
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
                    areNotifsGranted
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    color: areNotifsGranted ? pal.limeText : pal.textSecondary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          areNotifsGranted
                              ? 'Notificaciones activas'
                              : 'Notificaciones pendientes',
                          style: TextStyle(
                            color: pal.textTitle,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          areNotifsGranted
                              ? 'Recibirás avisos de pagos, cambios de orden y nuevos mensajes.'
                              : 'Activa las alertas para no perderte actualizaciones de tus órdenes.',
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
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (!areNotifsGranted && pwa.isNotificationSupported)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await pwa.requestNotificationPermission();
                        if (context.mounted) {
                          if (ok) {
                            await PushNotificationService.instance
                                .retryInitialize();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '¡Notificaciones activadas con éxito!',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(
                        Icons.notifications_active_outlined,
                        size: 16,
                      ),
                      label: const Text('Activar alertas'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pal.limeText,
                        side: BorderSide(color: pal.limeBorder),
                      ),
                    ),
                  if (pwa.isWeb && !pwa.isStandalone)
                    OutlinedButton.icon(
                      onPressed: () => A2hsGuideModal.show(context),
                      icon: const Icon(
                        Icons.add_to_home_screen_rounded,
                        size: 16,
                      ),
                      label: const Text('Cómo agregar a inicio'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pal.textTitle,
                        side: BorderSide(color: pal.navBorder),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.push(AppRoute.notificationSettings),
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: const Text('Ajustes de alertas'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: pal.textSecondary,
                      side: BorderSide(color: pal.navBorder),
                    ),
                  ),
                ],
              ),
            ],
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
                      Icon(
                        Icons.terminal_rounded,
                        size: 20,
                        color: pal.textSecondary,
                      ),
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
    BuildContext context,
    String title,
    OrderBookPalette pal,
  ) {
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
