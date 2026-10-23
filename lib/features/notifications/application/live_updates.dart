import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/security/app_lock.dart';

/// Lets tests and previews switch background updates off.
final liveUpdatesEnabledProvider = Provider<bool>((ref) => true);

final liveUpdatesProvider = Provider<LiveUpdates>(LiveUpdates.new);

/// Keeps the notification inbox current while the app is open.
///
/// With device storage, reminders are raised here as deadlines approach. With
/// a server, the server schedules reminders and teammates' changes arrive by
/// refreshing the workspace. The app calls [tick] each minute, on resume and
/// when the workspace or organisation changes; new arrivals then surface in
/// the live banner.
class LiveUpdates {
  final Ref ref;
  LiveUpdates(this.ref);
  bool _busy = false;

  Future<void> tick() async {
    if (_busy || !ref.read(liveUpdatesEnabledProvider)) return;
    final actor = ref.read(authProvider).value;
    if (actor == null ||
        ref.read(workspaceProvider).value == null ||
        ref.read(appLockProvider).locked) {
      return;
    }
    _busy = true;
    try {
      final workspace = ref.read(workspaceProvider.notifier);
      if (ref.read(storageProvider).isDevice) {
        final added = await ref
            .read(repositoryProvider)
            .syncReminders(
              ref.read(currentUserProvider),
              ref.read(organisationProvider).id,
              ref.read(todayProvider),
              overdueAlerts: ref.read(settingsProvider)['overdue'] ?? true,
            );
        if (added > 0) await workspace.refresh();
      } else {
        final offline =
            ref
                .read(connectivityProvider)
                .value
                ?.contains(ConnectivityResult.none) ??
            false;
        if (!offline) await workspace.refresh();
      }
    } catch (_) {
      // A missed update is retried on the next tick.
    } finally {
      _busy = false;
    }
  }
}
