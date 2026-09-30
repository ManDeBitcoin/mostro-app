import 'package:flutter/foundation.dart';
import 'pwa_service_stub.dart' if (dart.library.js_interop) 'pwa_service_web.dart';

/// Platform-agnostic interface for Progressive Web App (PWA), Add to Home Screen (A2HS),
/// and browser push capability checks.
abstract class PwaService {
  static PwaService get instance => getPwaService();

  /// Whether the app is currently running inside a web browser.
  bool get isWeb => kIsWeb;

  /// Whether the application is running in standalone mode (installed as a PWA / Added to Home Screen).
  bool get isStandalone;

  /// Whether the client browser is running on an iOS device (iPhone/iPad).
  bool get isIos;

  /// Whether the client browser is running on an Android device.
  bool get isAndroid;

  /// Whether the host environment supports system notifications.
  bool get isNotificationSupported;

  /// Whether notifications permission has already been granted.
  bool get areNotificationsGranted;

  /// Request notification permissions from the browser/OS.
  Future<bool> requestNotificationPermission();
}
