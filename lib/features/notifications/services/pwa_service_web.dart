import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'package:mostro/features/notifications/services/pwa_service.dart';

PwaService getPwaService() => PwaServiceWeb();

class PwaServiceWeb implements PwaService {
  @override
  bool get isWeb => true;

  @override
  bool get isStandalone {
    try {
      final nav = web.window.navigator as JSObject;
      final isStandaloneNav = nav.has('standalone')
          ? (nav['standalone'] as JSBoolean?)?.toDart ?? false
          : false;
      final isStandaloneMedia =
          web.window.matchMedia('(display-mode: standalone)').matches;
      return isStandaloneNav || isStandaloneMedia;
    } catch (e) {
      debugPrint('[pwa] isStandalone error: $e');
      return false;
    }
  }

  @override
  bool get isIos {
    try {
      final ua = web.window.navigator.userAgent.toLowerCase();
      return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isAndroid {
    try {
      final ua = web.window.navigator.userAgent.toLowerCase();
      return ua.contains('android');
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isNotificationSupported =>
      globalContext.has('Notification') &&
      (web.window.navigator as JSObject).has('serviceWorker');

  @override
  bool get areNotificationsGranted {
    try {
      if (!globalContext.has('Notification')) return false;
      final notif = globalContext['Notification'] as JSObject;
      return (notif['permission'] as JSString?)?.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    try {
      if (!globalContext.has('Notification')) return false;
      final notif = globalContext['Notification'] as JSObject;
      final promise =
          notif.callMethod<JSPromise<JSString>>('requestPermission'.toJS);
      final res = await promise.toDart;
      return res.toDart == 'granted';
    } catch (e) {
      debugPrint('[pwa] requestNotificationPermission error: $e');
      return false;
    }
  }
}
