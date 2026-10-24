import 'dart:async';

abstract interface class NotificationService {
  Stream<String> get dueItemLinks;

  /// Opens an obligation, for example when its notification is tapped.
  void openDueItem(String id);
  Future<bool> requestPermission();
  Future<void> registerDevice(String token);
  Future<void> dispose();
}

// The demo inbox is repository-backed. A push adapter can publish item IDs here.
class DemoNotificationService implements NotificationService {
  final _links = StreamController<String>.broadcast();
  @override
  Stream<String> get dueItemLinks => _links.stream;
  @override
  void openDueItem(String id) => _links.add(id);
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> registerDevice(String token) async {}
  @override
  Future<void> dispose() => _links.close();
}
