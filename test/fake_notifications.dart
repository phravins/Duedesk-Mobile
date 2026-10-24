import 'package:duedesk/features/notifications/application/system_notifications.dart';
import 'package:duedesk/features/notifications/domain/reminders.dart';

/// Records what would be handed to the phone's notification centre.
class FakeSystemNotifications implements SystemNotifications {
  List<PlannedReminder> scheduled = const [];
  void Function(String itemId)? tap;
  String? launchedBy;
  int permissionRequests = 0, cancels = 0;
  bool allow = true;

  @override
  Future<void> initialize(void Function(String itemId) onOpen) async =>
      tap = onOpen;
  @override
  Future<String?> launchItem() async => launchedBy;
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return allow;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async =>
      scheduled = reminders;
  @override
  Future<void> cancelAll() async {
    cancels++;
    scheduled = const [];
  }
}
