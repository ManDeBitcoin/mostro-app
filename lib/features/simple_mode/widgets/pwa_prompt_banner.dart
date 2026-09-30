import 'package:flutter/material.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/notifications/services/pwa_service.dart';
import 'package:mostro/features/simple_mode/widgets/a2hs_guide_modal.dart';

/// Banner shown on web browser sessions when the app is not running in standalone mode (A2HS).
class PwaPromptBanner extends StatefulWidget {
  const PwaPromptBanner({super.key});

  @override
  State<PwaPromptBanner> createState() => _PwaPromptBannerState();
}

class _PwaPromptBannerState extends State<PwaPromptBanner> {
  static bool _sessionDismissed = false;

  @override
  Widget build(BuildContext context) {
    final pwa = PwaService.instance;
    if (!pwa.isWeb || pwa.isStandalone || _sessionDismissed) {
      return const SizedBox.shrink();
    }

    final pal = OrderBookPalette.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: pal.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.limeBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.add_to_home_screen_rounded, color: pal.limeText, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Agrega Mostro a Inicio',
                  style: TextStyle(
                    color: pal.textTitle,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Recibe notificaciones en segundo plano de tus órdenes y pagos.',
                  style: TextStyle(
                    color: pal.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => A2hsGuideModal.show(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Instalar',
              style: TextStyle(
                color: pal.limeText,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 16, color: pal.textSecondary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _sessionDismissed = true),
          ),
        ],
      ),
    );
  }
}
