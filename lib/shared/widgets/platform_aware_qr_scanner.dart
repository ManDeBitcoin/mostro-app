import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Platform-aware QR scanner.
///
/// On **iOS, Android, and desktop** (non-web): opens the device camera using
/// `mobile_scanner`.
/// On **web with HTTPS**: attempts to open the camera via `mobile_scanner`;
/// if the browser denies permission or the camera fails to start, falls back
/// to a paste-from-clipboard text field.
/// On **web without HTTPS** (or when camera access is unavailable): shows the
/// paste-from-clipboard text field directly.
///
/// [onDetected] is called exactly once with the decoded string as soon as a
/// QR code is scanned or the user submits pasted content.
class PlatformAwareQrScanner extends StatefulWidget {
  const PlatformAwareQrScanner({
    super.key,
    required this.onDetected,
    this.hint = 'Paste or scan a QR code',
  });

  /// Called with the raw string value when a QR code is detected or submitted.
  final void Function(String value) onDetected;

  /// Placeholder text shown in the paste field (web only).
  final String hint;

  @override
  State<PlatformAwareQrScanner> createState() => _PlatformAwareQrScannerState();
}

class _PlatformAwareQrScannerState extends State<PlatformAwareQrScanner> {
  final _controller = TextEditingController();
  String? _errorText;
  bool _hasEmitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _emitOnce(String value) {
    if (_hasEmitted) return;
    _hasEmitted = true;
    widget.onDetected(value);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) setState(() => _errorText = AppLocalizations.of(context).clipboardEmptyError);
      return;
    }
    if (!mounted) return;
    setState(() => _errorText = null);
    _emitOnce(text);
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _errorText = AppLocalizations.of(context).enterValueError);
      return;
    }
    _emitOnce(text);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _WebScannerWithFallback(
        onDetected: _emitOnce,
        controller: _controller,
        errorText: _errorText,
        hint: widget.hint,
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
        onPaste: _pasteFromClipboard,
        onSubmit: _submit,
      );
    }
    return _CameraScanner(onDetected: widget.onDetected);
  }
}

// ── Camera scanner (native / desktop) ────────────────────────────────────────

class _CameraScanner extends StatefulWidget {
  const _CameraScanner({required this.onDetected});
  final void Function(String) onDetected;

  @override
  State<_CameraScanner> createState() => _CameraScannerState();
}

class _CameraScannerState extends State<_CameraScanner> {
  bool _detected = false;

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      onDetect: (capture) {
        if (_detected) return;
        final raw = capture.barcodes.firstOrNull?.rawValue?.trim();
        if (raw != null && raw.isNotEmpty) {
          _detected = true;
          widget.onDetected(raw);
        }
      },
    );
  }
}

// ── Web: try camera first, fall back to paste ────────────────────────────────

/// On web, attempts to start the camera scanner. If the camera fails to start
/// (permission denied, no camera, HTTP-only), shows the paste/type fallback
/// automatically. The user can also switch manually between modes.
class _WebScannerWithFallback extends StatefulWidget {
  const _WebScannerWithFallback({
    required this.onDetected,
    required this.controller,
    required this.errorText,
    required this.hint,
    required this.onChanged,
    required this.onPaste,
    required this.onSubmit,
  });

  final void Function(String) onDetected;
  final TextEditingController controller;
  final String? errorText;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onPaste;
  final VoidCallback onSubmit;

  @override
  State<_WebScannerWithFallback> createState() =>
      _WebScannerWithFallbackState();
}

class _WebScannerWithFallbackState extends State<_WebScannerWithFallback> {
  bool _showCamera = true;
  bool _cameraFailed = false;
  bool _detected = false;
  late final MobileScannerController _scannerController;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController();
    _tryStartCamera();
  }

  Future<void> _tryStartCamera() async {
    try {
      await _scannerController.start();
    } catch (_) {
      if (mounted) {
        setState(() {
          _showCamera = false;
          _cameraFailed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_showCamera && !_cameraFailed) {
      return Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _scannerController,
              errorBuilder: (context, error) {
                // Camera error — switch to fallback automatically.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_cameraFailed) {
                    setState(() {
                      _showCamera = false;
                      _cameraFailed = true;
                    });
                  }
                });
                return Center(
                  child: Text(
                    l10n.enterValueError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                );
              },
              onDetect: (capture) {
                if (_detected) return;
                final raw = capture.barcodes.firstOrNull?.rawValue?.trim();
                if (raw != null && raw.isNotEmpty) {
                  _detected = true;
                  widget.onDetected(raw);
                }
              },
            ),
          ),
          // Button to switch to manual input
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextButton.icon(
              onPressed: () => setState(() => _showCamera = false),
              icon: const Icon(Icons.keyboard),
              label: Text(l10n.pasteButtonLabel),
            ),
          ),
        ],
      );
    }

    // Paste/type fallback
    return Column(
      children: [
        Expanded(
          child: _WebFallback(
            controller: widget.controller,
            errorText: widget.errorText,
            hint: widget.hint,
            onChanged: widget.onChanged,
            onPaste: widget.onPaste,
            onSubmit: widget.onSubmit,
          ),
        ),
        if (!_cameraFailed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: TextButton.icon(
              onPressed: () => setState(() => _showCamera = true),
              icon: const Icon(Icons.camera_alt),
              label: Text(l10n.scanQrButtonLabel),
            ),
          ),
      ],
    );
  }
}

// ── Web fallback (paste / type) ───────────────────────────────────────────────

class _WebFallback extends StatelessWidget {
  const _WebFallback({
    required this.controller,
    required this.errorText,
    required this.hint,
    required this.onChanged,
    required this.onPaste,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? errorText;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onPaste;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) {
      throw StateError('AppColors theme extension must be registered');
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppLocalizations.of(context).pasteQrCodeHeading,
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
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPaste,
                  icon: const Icon(Icons.content_paste),
                  label: Text(AppLocalizations.of(context).pasteButtonLabel),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: onSubmit,
                  child: Text(AppLocalizations.of(context).submitButtonLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
