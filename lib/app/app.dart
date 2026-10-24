import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/security/app_lock.dart';
import '../core/theme/app_theme.dart';
import '../features/notifications/application/live_updates.dart';
import '../features/notifications/application/reminder_scheduler.dart';
import 'app_frame.dart';
import 'providers.dart';
import 'router.dart';

class DueDeskApp extends ConsumerStatefulWidget {
  const DueDeskApp({super.key});
  @override
  ConsumerState<DueDeskApp> createState() => _AppState();
}

class _AppState extends ConsumerState<DueDeskApp> with WidgetsBindingObserver {
  Timer? _clock;
  StreamSubscription<String>? _notifications;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      ref.invalidate(todayProvider);
      ref.read(appLockProvider.notifier).checkIdle();
      ref.read(liveUpdatesProvider).tick();
    });
    // Check for reminders as soon as a workspace opens or the organisation
    // changes, rather than waiting for the next minute.
    ref.listenManual(workspaceProvider, (previous, next) {
      if (previous?.value == null && next.value != null) _tickSoon();
    });
    ref.listenManual(currentOrganisationProvider, (_, _) => _tickSoon());
    if (ref.read(workspaceProvider).hasValue) _tickSoon();
    ref.listenManual(appLockProvider.select((s) => s.locked), (was, locked) {
      if (was == true && !locked) _tickSoon();
    });
    _notifications = ref.read(notificationServiceProvider).dueItemLinks.listen((
      id,
    ) {
      if (mounted) {
        ref.read(routerProvider).go('/due/${Uri.encodeComponent(id)}');
      }
    });
    // Phone notifications for when the app is closed; started after the
    // link listener so a notification that launched the app opens it.
    ref.read(reminderSchedulerProvider).start();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _notifications?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _tickSoon() => Future.microtask(() {
    if (mounted) ref.read(liveUpdatesProvider).tick();
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider.notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        ref.read(appObscuredProvider.notifier).set(false);
        lock.foregrounded();
        ref.invalidate(todayProvider);
        _tickSoon();
        ref.read(reminderSchedulerProvider).schedule();
      case AppLifecycleState.inactive:
        ref.read(appObscuredProvider.notifier).set(true);
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        ref.read(appObscuredProvider.notifier).set(true);
        lock.backgrounded();
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'DueDesk',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.theme(Brightness.light),
    darkTheme: AppTheme.theme(Brightness.dark),
    themeMode: ref.watch(themeProvider),
    routerConfig: ref.watch(routerProvider),
    builder: (context, child) => AppFrame(child: child ?? const SizedBox()),
  );
}
