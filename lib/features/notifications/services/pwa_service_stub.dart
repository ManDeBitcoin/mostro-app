import 'pwa_service.dart';

PwaService getPwaService() => PwaServiceStub();

class PwaServiceStub implements PwaService {
  @override
  bool get isWeb => false;

  @override
  bool get isStandalone => false;

  @override
  bool get isIos => false;

  @override
  bool get isAndroid => false;

  @override
  bool get isNotificationSupported => true;

  @override
  bool get areNotificationsGranted => true;

  @override
  Future<bool> requestNotificationPermission() async => true;
}
