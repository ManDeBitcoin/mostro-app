import 'package:flutter/material.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/notifications/services/pwa_service.dart';
import 'package:mostro/features/notifications/services/push_notification_service.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// Modal dialog providing step-by-step guidance for adding Mostro to the Home Screen (A2HS)
/// and enabling background notifications.
class A2hsGuideModal extends StatefulWidget {
  const A2hsGuideModal({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const A2hsGuideModal(),
    );
  }

  @override
  State<A2hsGuideModal> createState() => _A2hsGuideModalState();
}

class _A2hsGuideModalState extends State<A2hsGuideModal> {
  int _activePlatform = 0; // 0: iOS, 1: Android, 2: Desktop

  @override
  void initState() {
    super.initState();
    final pwa = PwaService.instance;
    if (pwa.isIos) {
      _activePlatform = 0;
    } else if (pwa.isAndroid) {
      _activePlatform = 1;
    } else {
      _activePlatform = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final theme = Theme.of(context);
    final pwa = PwaService.instance;

    return MostroDialog(
      title: 'Agregar a Pantalla de Inicio',
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: pal.limeBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add_to_home_screen_rounded,
                    color: pal.limeText,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Instala Mostro para recibir notificaciones en segundo plano y acceder al instante.',
                    style: TextStyle(
                      color: pal.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Platform switch chips
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('iOS (Safari)')),
                    selected: _activePlatform == 0,
                    onSelected: (val) {
                      if (val) setState(() => _activePlatform = 0);
                    },
                    selectedColor: pal.limeBorder,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: _activePlatform == 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Android')),
                    selected: _activePlatform == 1,
                    onSelected: (val) {
                      if (val) setState(() => _activePlatform = 1);
                    },
                    selectedColor: pal.limeBorder,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: _activePlatform == 1
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Escritorio')),
                    selected: _activePlatform == 2,
                    onSelected: (val) {
                      if (val) setState(() => _activePlatform = 2);
                    },
                    selectedColor: pal.limeBorder,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: _activePlatform == 2
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Step list
            if (_activePlatform == 0) ...[
              _buildStep(
                number: '1',
                title: 'Toca el botón Compartir',
                description:
                    'En la barra inferior de Safari, pulsa el icono de compartir (el cuadrado con la flecha hacia arriba).',
                icon: Icons.ios_share_rounded,
                pal: pal,
              ),
              _buildStep(
                number: '2',
                title: 'Selecciona "Agregar a pantalla de inicio"',
                description:
                    'Desplázate hacia abajo en el menú de opciones y selecciona "Agregar a pantalla de inicio".',
                icon: Icons.add_box_outlined,
                pal: pal,
              ),
              _buildStep(
                number: '3',
                title: 'Confirma y abre desde el Inicio',
                description:
                    'Pulsa "Agregar". Abre Mostro desde el icono nuevo en tu pantalla y permite las notificaciones cuando el sistema te lo pida.',
                icon: Icons.check_circle_outline_rounded,
                pal: pal,
              ),
            ] else if (_activePlatform == 1) ...[
              _buildStep(
                number: '1',
                title: 'Toca el menú de Chrome',
                description:
                    'Pulsa los tres puntos verticales (⋮) en la esquina superior derecha del navegador.',
                icon: Icons.more_vert_rounded,
                pal: pal,
              ),
              _buildStep(
                number: '2',
                title: 'Selecciona "Instalar aplicación"',
                description:
                    'O "Agregar a la pantalla principal" según tu versión de Android.',
                icon: Icons.download_for_offline_outlined,
                pal: pal,
              ),
              _buildStep(
                number: '3',
                title: 'Listo para recibir notificaciones',
                description:
                    'Al abrir la app instalada, recibirás alertas automáticas de órdenes y mensajes.',
                icon: Icons.notifications_active_outlined,
                pal: pal,
              ),
            ] else ...[
              _buildStep(
                number: '1',
                title: 'Haz clic en el icono de instalación',
                description:
                    'En la barra de direcciones de Chrome, Brave o Edge, haz clic en el icono de instalar (o en el menú ⋮ > Instalar Mostro).',
                icon: Icons.desktop_windows_outlined,
                pal: pal,
              ),
              _buildStep(
                number: '2',
                title: 'Confirma la instalación',
                description:
                    'Se creará una ventana independiente de Mostro lista para operar.',
                icon: Icons.launch_rounded,
                pal: pal,
              ),
            ],

            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pal.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: pal.navBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: pal.limeText, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tus claves privadas permanecen 100% en tu dispositivo y nunca se comparten.',
                      style: TextStyle(color: pal.textSecondary, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      primary: ModalAction(
        label: 'Entendido',
        onPressed: () => Navigator.pop(context),
      ),
      secondary: (!pwa.areNotificationsGranted && pwa.isNotificationSupported)
          ? ModalAction(
              label: 'Activar Alertas',
              onPressed: () async {
                Navigator.pop(context);
                final granted = await pwa.requestNotificationPermission();
                if (context.mounted) {
                  if (granted) {
                    await PushNotificationService.instance.retryInitialize();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('¡Notificaciones activadas con éxito!'),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Permiso no concedido. Puedes habilitarlo en los ajustes del navegador.',
                        ),
                      ),
                    );
                  }
                }
              },
            )
          : null,
    );
  }

  Widget _buildStep({
    required String number,
    required String title,
    required String description,
    required IconData icon,
    required OrderBookPalette pal,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: pal.limeBorder,
            child: Text(
              number,
              style: TextStyle(
                color: pal.limeText,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: pal.textTitle),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: pal.textTitle,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    color: pal.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
