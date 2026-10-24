import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../domain/reminders.dart';

/// The phone's own notification centre: reminders scheduled here arrive
/// even when DueDesk is closed or the device has restarted.
abstract interface class SystemNotifications {
  /// Prepares the channel; [onOpen] receives the obligation ID when a
  /// notification is tapped while the app is running.
  Future<void> initialize(void Function(String itemId) onOpen);

  /// The obligation whose notification launched the app, if any.
  Future<String?> launchItem();

  /// Asks the person for permission. Returns whether alerts are allowed.
  Future<bool> requestPermission();

  /// Makes the scheduled set exactly [reminders]: new ones are added,
  /// changed ones replaced and ones no longer wanted cancelled.
  Future<void> replaceAll(List<PlannedReminder> reminders);

  /// Cancels every scheduled reminder, for example on sign-out.
  Future<void> cancelAll();
}

class LocalSystemNotifications implements SystemNotifications {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _android = AndroidNotificationDetails(
    'deadline_reminders',
    'Deadline reminders',
    channelDescription: 'Reminders before obligations fall due',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    // Content stays hidden on a locked screen until the phone is unlocked.
    visibility: NotificationVisibility.private,
  );

  /// While DueDesk is open its own notification bar shows the reminder, so
  /// iOS only files it in Notification Centre.
  static const _ios = DarwinNotificationDetails(
    threadIdentifier: 'deadline_reminders',
    presentBanner: false,
    presentList: true,
    presentSound: false,
  );

  Future<T?> _guard<T>(Future<T> Function() action) async {
    if (kIsWeb) return null;
    try {
      return await action();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> initialize(void Function(String itemId) onOpen) async {
    final ok = await _guard(
      () => _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_duedesk'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final id = response.payload;
          if (id != null && id.isNotEmpty) onOpen(id);
        },
      ),
    );
    _ready = ok ?? false;
  }

  @override
  Future<String?> launchItem() async {
    if (!_ready) return null;
    final details = await _guard(_plugin.getNotificationAppLaunchDetails);
    if (details == null || !details.didNotificationLaunchApp) return null;
    final id = details.notificationResponse?.payload;
    return id == null || id.isEmpty ? null : id;
  }

  @override
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final granted = await _guard(() async {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return ios.requestPermissions(alert: true, badge: true, sound: true);
      }
      return _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    });
    return granted ?? false;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async {
    if (!_ready) return;
    final wanted = {for (final r in reminders) r.id};
    final pending = await _guard(_plugin.pendingNotificationRequests) ?? [];
    for (final p in pending) {
      if (!wanted.contains(p.id)) await _guard(() => _plugin.cancel(id: p.id));
    }
    for (final r in reminders) {
      await _guard(
        () => _plugin.zonedSchedule(
          id: r.id,
          scheduledDate: r.when,
          title: r.title,
          body: r.body,
          payload: r.itemId,
          notificationDetails: const NotificationDetails(
            android: _android,
            iOS: _ios,
          ),
          // Within a few minutes of the hour; needs no exact-alarm permission.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        ),
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    if (_ready) await _guard(_plugin.cancelAllPendingNotifications);
  }
}
