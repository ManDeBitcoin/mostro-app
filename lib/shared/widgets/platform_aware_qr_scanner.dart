import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Platform-aware QR scanner.
///
/// Displays a live camera feed with an alignment viewfinder overlay
/// and immediate hardware release upon detection, manual mode toggle,
/// or disposal.
///
/// On web and desktop environments where camera permissions are denied or
/// hardware is unavailable, falls back gracefully to a manual input form.
///
/// [onDetected] is called exactly once with the decoded string value.
class PlatformAwareQrScanner extends StatefulWidget {
  const PlatformAwareQrScanner({
    super.key,
    required this.onDetected,
    this.hint = 'Paste or scan a QR code',
  });

  /// Called with the raw string value when a QR code is detected or submitted.
  final void Function(String value) onDetected;

  /// Placeholder text shown in the paste field.
  final String hint;

  @override
  State<PlatformAwareQrScanner> createState() => _PlatformAwareQrScannerState();
}

class _PlatformAwareQrScannerState extends State<PlatformAwareQrScanner> {
  late final MobileScannerController _scannerController;
  final TextEditingController _pasteController = TextEditingController();
  bool _hasEmitted = false;
  bool _showCamera = true;
  bool _cameraUnavailable = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      try {
        MobileScannerPlatform.instance.setWebBarcodeReader(WebBarcodeReader.zxingJs);
      } catch (_) {}
    }
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
      autoStart: true,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _emitOnce(String value) async {
    if (_hasEmitted) return;
    _hasEmitted = true;
    try {
      await _scannerController.stop();
    } catch (_) {}
    if (mounted) {
      widget.onDetected(value);
    }
  }

  Future<void> _switchToManual() async {
    try {
      await _scannerController.stop();
    } catch (_) {}
    if (mounted) {
      setState(() => _showCamera = false);
    }
  }

  Future<void> _switchToCamera() async {
    if (mounted) {
      setState(() => _showCamera = true);
    }
    try {
      await _scannerController.start();
    } catch (_) {}
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) {
        setState(() => _errorText = AppLocalizations.of(context).clipboardEmptyError);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _errorText = null);
    await _emitOnce(text);
  }

  Future<void> _submitManual() async {
    final text = _pasteController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorText = AppLocalizations.of(context).enterValueError);
      return;
    }
    await _emitOnce(text);
  }

  @override
  Widget build(BuildContext context) {
    if (_showCamera && !_cameraUnavailable) {
      return Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _scannerController,
              fit: BoxFit.cover,
              errorBuilder: (context, error) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _showCamera) {
                    _scannerController.stop();
                    setState(() {
                      _showCamera = false;
                      _cameraUnavailable = true;
                    });
                  }
                });
                return const SizedBox.shrink();
              },
              onDetect: (capture) {
                if (_hasEmitted) return;
                final raw = capture.barcodes.firstOrNull?.rawValue?.trim();
                if (raw != null && raw.isNotEmpty) {
                  _emitOnce(raw);
                }
              },
            ),
          ),
          Positioned.fill(
            child: _ScannerOverlay(
              onSwitchToManual: _switchToManual,
              onToggleTorch: () => _scannerController.toggleTorch(),
            ),
          ),
        ],
      );
    }

    return _ManualFallback(
      controller: _pasteController,
      errorText: _errorText,
      hint: widget.hint,
      canSwitchToCamera: !_cameraUnavailable,
      onChanged: (_) {
        if (_errorText != null) setState(() => _errorText = null);
      },
      onPaste: _pasteFromClipboard,
      onSubmit: _submitManual,
      onSwitchToCamera: _switchToCamera,
    );
  }
}

// ── Viewfinder overlay ────────────────────────────────────────────────────────

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({
    required this.onSwitchToManual,
    required this.onToggleTorch,
  });

  final VoidCallback onSwitchToManual;
  final VoidCallback onToggleTorch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final scanBoxSize = math.min(
      size.width * 0.70,
      math.min(size.height * 0.45, 280.0),
    );

    return Stack(
      children: [
        // Cutout scrim with dark background and clear center box
        Positioned.fill(
          child: CustomPaint(
            painter: _ScannerCutoutPainter(
              boxSize: scanBoxSize,
              borderColor: const Color(0xFFC4F43A),
              scrimColor: Colors.black.withValues(alpha: 0.65),
            ),
          ),
        ),
        // Instructions pill below the viewfinder box
        Align(
          alignment: Alignment.center,
          child: Padding(
            padding: EdgeInsets.only(top: scanBoxSize + 40.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.qr_code_scanner,
                    color: Color(0xFFC4F43A),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.scanQrCodeTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Bottom toolbar: Manual input toggle + Flashlight toggle
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onPressed: onSwitchToManual,
                  icon: const Icon(Icons.keyboard_outlined, size: 20),
                  label: Text(l10n.pasteButtonLabel),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.7),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onToggleTorch,
                  icon: const Icon(Icons.flash_on, size: 20),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Cutout painter ────────────────────────────────────────────────────────────

class _ScannerCutoutPainter extends CustomPainter {
  const _ScannerCutoutPainter({
    required this.boxSize,
    required this.borderColor,
    required this.scrimColor,
  });

  static const double borderRadius = 18.0;
  static const double cornerLength = 30.0;
  static const double strokeWidth = 3.5;

  final double boxSize;
  final Color borderColor;
  final Color scrimColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(
      center: center,
      width: boxSize,
      height: boxSize,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(borderRadius),
    );

    // Dark scrim with transparent cutout
    final scrimPaint = Paint()
      ..color = scrimColor
      ..style = PaintingStyle.fill;

    final scrimPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(scrimPath, scrimPaint);

    // Subtle outline of the viewfinder
    final borderPaint = Paint()
      ..color = borderColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, borderPaint);

    // Highlighted corner brackets
    final cornerPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final left = rect.left;
    final top = rect.top;
    final right = rect.right;
    final bottom = rect.bottom;
    const radius = Radius.circular(borderRadius);

    // Top-left
    final topLeft = Path()
      ..moveTo(left, top + cornerLength)
      ..lineTo(left, top + borderRadius)
      ..arcToPoint(Offset(left + borderRadius, top), radius: radius)
      ..lineTo(left + cornerLength, top);
    canvas.drawPath(topLeft, cornerPaint);

    // Top-right
    final topRight = Path()
      ..moveTo(right - cornerLength, top)
      ..lineTo(right - borderRadius, top)
      ..arcToPoint(Offset(right, top + borderRadius), radius: radius)
      ..lineTo(right, top + cornerLength);
    canvas.drawPath(topRight, cornerPaint);

    // Bottom-left
    final bottomLeft = Path()
      ..moveTo(left, bottom - cornerLength)
      ..lineTo(left, bottom - borderRadius)
      ..arcToPoint(Offset(left + borderRadius, bottom), radius: radius)
      ..lineTo(left + cornerLength, bottom);
    canvas.drawPath(bottomLeft, cornerPaint);

    // Bottom-right
    final bottomRight = Path()
      ..moveTo(right - cornerLength, bottom)
      ..lineTo(right - borderRadius, bottom)
      ..arcToPoint(Offset(right, bottom - borderRadius), radius: radius)
      ..lineTo(right, bottom - cornerLength);
    canvas.drawPath(bottomRight, cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _ScannerCutoutPainter oldDelegate) {
    return oldDelegate.boxSize != boxSize ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.scrimColor != scrimColor;
  }
}

// ── Manual fallback (paste / type) ────────────────────────────────────────────

class _ManualFallback extends StatelessWidget {
  const _ManualFallback({
    required this.controller,
    required this.errorText,
    required this.hint,
    required this.canSwitchToCamera,
    required this.onChanged,
    required this.onPaste,
    required this.onSubmit,
    required this.onSwitchToCamera,
  });

  final TextEditingController controller;
  final String? errorText;
  final String hint;
  final bool canSwitchToCamera;
  final ValueChanged<String> onChanged;
  final VoidCallback onPaste;
  final VoidCallback onSubmit;
  final VoidCallback onSwitchToCamera;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) {
      throw StateError('AppColors theme extension must be registered');
    }
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.pasteQrCodeHeading,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              errorText: errorText,
            ),
            autocorrect: false,
            enableSuggestions: false,
            onChanged: onChanged,
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPaste,
                  icon: const Icon(Icons.content_paste),
                  label: Text(l10n.pasteButtonLabel),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: onSubmit,
                  child: Text(l10n.submitButtonLabel),
                ),
              ),
            ],
          ),
          if (canSwitchToCamera) ...[
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: TextButton.icon(
                onPressed: onSwitchToCamera,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(l10n.scanQrButtonLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
