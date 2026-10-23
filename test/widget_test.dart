import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:duedesk/app/app.dart';
import 'package:duedesk/app/app_frame.dart';
import 'package:duedesk/app/providers.dart';
import 'package:duedesk/app/router.dart';
import 'package:duedesk/core/security/app_lock.dart';
import 'package:duedesk/core/storage/local_store.dart';
import 'package:duedesk/features/notifications/application/live_updates.dart';
import 'package:duedesk/features/security/presentation/lock_screen.dart';
import 'package:duedesk/core/storage/storage_settings.dart';
import 'package:duedesk/features/auth/data/auth_repositories.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:duedesk/core/widgets/glass.dart';
import 'package:duedesk/shared/widgets/due_widgets.dart';
import 'package:duedesk/features/due_items/data/demo_seed.dart';
import 'package:duedesk/shared/models/models.dart';

final captureKey = GlobalKey();

class FakeBiometrics extends BiometricAuth {
  bool enrolled = true, accept = true;
  int prompts = 0;
  @override
  Future<bool> available() async => enrolled;
  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return accept;
  }
}

Future<ProviderContainer> boot(
  WidgetTester tester, {
  bool signedIn = true,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool live = false,
  Map<String, String> secure = const {},
}) async {
  FlutterSecureStorage.setMockInitialValues({...secure});
  tz.initializeTimeZones();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  await (FontLoader(
    'Inter',
  )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
  await (FontLoader(
    'NotoSerif',
  )..addFont(rootBundle.load('assets/fonts/NotoSerif-Medium.ttf'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'onboarding': true,
    if (signedIn) 'demoUser': 'management',
  });
  final prefs = await SharedPreferences.getInstance();
  final store = MemoryLocalStore();
  await store.write(demoSeed());
  final container = ProviderContainer(
    overrides: [
      preferencesProvider.overrideWithValue(prefs),
      localStoreProvider.overrideWithValue(store),
      connectivityProvider.overrideWith(
        (ref) => Stream.value([ConnectivityResult.wifi]),
      ),
      // Reminder banners are covered by their own tests below.
      liveUpdatesEnabledProvider.overrideWithValue(live),
      passcodeHasherProvider.overrideWithValue(
        const PasscodeHasher(iterations: 1000),
      ),
      biometricAuthProvider.overrideWithValue(FakeBiometrics()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authProvider.future);
  if (signedIn) await container.read(workspaceProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(key: captureKey, child: const DueDeskApp()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  for (
    var attempt = 0;
    attempt < 24 && finder.hitTestable().evaluate().isEmpty;
    attempt++
  ) {
    await tester.dragFrom(const Offset(190, 650), const Offset(0, -420));
    await tester.pumpAndSettle();
  }
  expect(finder.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets('Login validates email/password and signs in', (tester) async {
    final c = await boot(tester, signedIn: false);
    c.read(routerProvider).go('/login');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'demo@duedesk.app',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'demo123');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Continue'));
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(c.read(authProvider).value?.id, 'management');
    expect(find.text('Due overview'), findsOneWidget);
  });
  testWidgets('Register validates mobile and password and creates account', (
    tester,
  ) async {
    final c = await boot(tester, signedIn: false);
    c.read(routerProvider).go('/register');
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, 'Create account');
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.text('Enter your full name.'), findsOneWidget);
    expect(find.text('Enter a 10-digit Indian mobile number.'), findsOneWidget);
    expect(find.text('Use at least 10 characters.'), findsOneWidget);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Asha Sharma');
    await tester.enterText(fields.at(1), 'asha@example.in');
    await tester.enterText(fields.at(2), '98765 43210');
    await tester.enterText(fields.at(3), 'local-password-1');
    await tester.ensureVisible(create);
    await tester.runAsync(() async {
      await tester.tap(create);
      for (var i = 0; i < 50 && c.read(authProvider).value == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();
    final user = c.read(authProvider).value!;
    expect(user.name, 'Asha Sharma');
    expect(user.phone, '+919876543210');
  });
  testWidgets('Auth pages fit phones with large text and wide windows', (
    tester,
  ) async {
    for (final (size, scale, mode) in [
      (const Size(360, 640), 1.5, ThemeMode.light),
      (const Size(1440, 900), 1.0, ThemeMode.dark),
    ]) {
      final c = await boot(
        tester,
        signedIn: false,
        size: size,
        textScale: scale,
      );
      await c.read(themeProvider.notifier).set(mode);
      for (final route in ['/login', '/register', '/forgot-password']) {
        c.read(routerProvider).go(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), null, reason: '$route at $size');
        expect(find.text('DueDesk'), findsOneWidget);
      }
    }
  });
  testWidgets('Dashboard counts and navigation use repository data', (
    tester,
  ) async {
    final c = await boot(tester);
    expect(find.text('5 items need your attention'), findsOneWidget);
    await tester.tap(find.text('Review now'));
    await tester.pumpAndSettle();
    expect(
      c.read(routerProvider).routeInformationProvider.value.uri.path,
      '/due',
    );
    expect(find.text('5 obligations'), findsOneWidget);
  });
  testWidgets('Due card opens detail and completion preserves history', (
    tester,
  ) async {
    final c = await boot(tester);
    c.read(routerProvider).go('/due/gst');
    await tester.pumpAndSettle();
    expect(find.text('GSTR-3B Filing'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Complete'));
    await tester.pumpAndSettle();
    await reveal(
      tester,
      find.widgetWithText(FilledButton, 'Mark as Completed'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Mark as Completed'));
    await tester.pumpAndSettle();
    expect(find.text('One less thing to think about.'), findsOneWidget);
    expect(c.read(dueItemDetailProvider('gst'))!.completedBy, 'Management');
  });
  testWidgets('Create form validates required fields', (tester) async {
    final c = await boot(tester);
    c.read(routerProvider).go('/due/new');
    await tester.pumpAndSettle();
    await reveal(tester, find.widgetWithText(FilledButton, 'Create Due Item'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create Due Item'));
    await tester.pumpAndSettle();
    expect(find.text('Enter title.'), findsOneWidget);
    expect(find.text('Select category.'), findsOneWidget);
    expect(find.text('Select assign to.'), findsOneWidget);
  });
  testWidgets(
    'Create, edit and archive work through the actual form and detail actions',
    (tester) async {
      final c = await boot(tester);
      c.read(routerProvider).go('/due/new');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Equipment inspection',
      );
      final category = find.byWidgetPredicate(
        (w) => w is GlassDropdown<String> && w.label == 'Category',
      );
      await reveal(tester, category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GST').last);
      await tester.pumpAndSettle();
      final date = find.text('Select date').first;
      await reveal(tester, date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final assignee = find.byWidgetPredicate(
        (w) => w is GlassDropdown<String> && w.label == 'Assign to',
      );
      await reveal(tester, assignee);
      await tester.tap(assignee);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Management').last);
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.widgetWithText(FilledButton, 'Create Due Item'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create Due Item'));
      await tester.pumpAndSettle();
      final item = c
          .read(dueItemsProvider)
          .singleWhere((i) => i.title == 'Equipment inspection');
      expect(
        c.read(routerProvider).routeInformationProvider.value.uri.path,
        '/due/${item.id}',
      );
      c.read(routerProvider).go('/due/${item.id}/edit');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Equipment inspection revised',
      );
      await reveal(tester, find.widgetWithText(FilledButton, 'Save changes'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();
      expect(
        c.read(dueItemDetailProvider(item.id))!.title,
        'Equipment inspection revised',
      );
      await tester.tap(find.byTooltip('DueItem actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Archive DueItem'));
      await tester.pumpAndSettle();
      expect(
        c.read(dueItemDetailProvider(item.id))!.status,
        DueStatus.archived,
      );
    },
  );
  testWidgets('Search debounces and finds authority', (tester) async {
    final c = await boot(tester);
    c.read(routerProvider).go('/due');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'GST Portal');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(DueItemCard), findsOneWidget);
    expect(find.text('GSTR-3B Filing'), findsOneWidget);
  });
  testWidgets('Auth guard redirects unauthenticated deep route', (
    tester,
  ) async {
    final c = await boot(tester, signedIn: false);
    c.read(routerProvider).go('/due/gst');
    await tester.pumpAndSettle();
    expect(
      c.read(routerProvider).routeInformationProvider.value.uri.path,
      '/welcome',
    );
  });
  testWidgets('Organisation switching isolates lists and permissions', (
    tester,
  ) async {
    final c = await boot(tester);
    await c.read(currentOrganisationProvider.notifier).select('rootd');
    await tester.pumpAndSettle();
    expect(c.read(dueItemsProvider), hasLength(1));
    expect(find.text('Add Due Item'), findsNothing);
    c.read(routerProvider).go('/due/new');
    await tester.pumpAndSettle();
    expect(find.text('Access restricted'), findsOneWidget);
  });
  testWidgets('Appearance persists and every route renders at 360px', (
    tester,
  ) async {
    final c = await boot(tester, size: const Size(360, 800));
    await c.read(themeProvider.notifier).set(ThemeMode.dark);
    expect(c.read(preferencesProvider).getString('theme'), 'dark');
    for (final route in [
      '/home',
      '/due',
      '/due/gst',
      '/due/new',
      '/due/gst/edit',
      '/calendar',
      '/documents',
      '/notifications',
      '/more',
      '/company',
      '/team',
      '/team/invite',
      '/categories',
      '/activity',
      '/profile',
      '/settings/notifications',
      '/settings/appearance',
      '/settings/security',
      '/about',
    ]) {
      c.read(routerProvider).go(route);
      await tester.pumpAndSettle();
      expect(tester.takeException(), null, reason: route);
    }
  });
  testWidgets('Core screens support large text on a small phone', (
    tester,
  ) async {
    final c = await boot(tester, size: const Size(360, 640), textScale: 1.5);
    for (final route in [
      '/home',
      '/due',
      '/due/gst',
      '/calendar',
      '/onboarding',
    ]) {
      c.read(routerProvider).go(route);
      await tester.pumpAndSettle();
      expect(tester.takeException(), null, reason: route);
    }
  });
  testWidgets('Tablet dashboard renders without overflow', (tester) async {
    await boot(tester, size: const Size(1024, 1366));
    expect(tester.takeException(), null);
  });
  test('Custom scheme normalizes to a detail route', () {
    expect(normalizeDeepLink(Uri.parse('duedesk://due/gst')), '/due/gst');
  });
  testWidgets('Pinned obligations persist and remain scoped to the company', (
    tester,
  ) async {
    final c = await boot(tester);
    c.read(routerProvider).go('/due');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pin obligation').first);
    await tester.pumpAndSettle();
    final pinned = c.read(pinnedItemsProvider).single;
    c.invalidate(pinnedItemsProvider);
    expect(c.read(pinnedItemsProvider), contains(pinned));
    c.read(routerProvider).go('/due?filter=Pinned');
    await tester.pumpAndSettle();
    expect(find.text('1 obligations'), findsOneWidget);
    await c.read(currentOrganisationProvider.notifier).select('osworks');
    await tester.pumpAndSettle();
    expect(c.read(pinnedItemsProvider), isEmpty);
    await c.read(currentOrganisationProvider.notifier).select('realoffice');
    await tester.pumpAndSettle();
    expect(c.read(pinnedItemsProvider), contains(pinned));
    await tester.tap(find.byTooltip('Unpin obligation'));
    await tester.pumpAndSettle();
    expect(find.text('Keep priorities close.'), findsOneWidget);
  });
  testWidgets('Templates prefill obligations but require ownership and date', (
    tester,
  ) async {
    final c = await boot(tester);
    c.read(routerProvider).go('/due/new?templates=true');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insurance Renewal'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, 'Insurance Renewal'),
      findsOneWidget,
    );
    await reveal(tester, find.widgetWithText(FilledButton, 'Create Due Item'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create Due Item'));
    await tester.pumpAndSettle();
    expect(find.text('Select assign to.'), findsOneWidget);
    expect(c.read(dueItemsProvider).length, 8);
  });
  testWidgets('Date links select the right calendar day', (tester) async {
    final c = await boot(tester);
    c.read(routerProvider).go('/calendar?date=2026-11-12');
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Thursday, 12 November'));
    expect(tester.takeException(), null);
  });
  testWidgets('Wide layouts use a working navigation rail', (tester) async {
    final c = await boot(tester, size: const Size(1024, 900));
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Due'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      c.read(routerProvider).routeInformationProvider.value.uri.path,
      '/due',
    );
    expect(tester.takeException(), null);
  });
  testWidgets('Welcome lets people pick device or self-hosted storage', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final c = await boot(tester, signedIn: false);
    expect(c.read(storageProvider).mode, StorageMode.device);
    final chip = find.textContaining('This device');
    await reveal(tester, chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Self-hosted server'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Server address'),
      'http://due.example.com',
    );
    await tester.tap(find.text('Connect to server'));
    await tester.pumpAndSettle();
    expect(
      find.text('Use https:// for servers outside your local network.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Server address'),
      'due.example.com/',
    );
    await tester.tap(find.text('Connect to server'));
    await tester.pumpAndSettle();
    expect(c.read(storageProvider).mode, StorageMode.server);
    expect(c.read(storageProvider).serverUrl, 'https://due.example.com');
    expect(c.read(authRepositoryProvider), isA<ApiAuthRepository>());
    expect(c.read(preferencesProvider).getString('storageMode'), 'server');
    expect(find.text('Continue in demo mode'), findsNothing);
    expect(find.textContaining('due.example.com'), findsWidgets);
  });
  testWidgets('Switching storage from Settings signs out first', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final c = await boot(tester);
    c.read(routerProvider).push('/settings/storage');
    await tester.pumpAndSettle();
    expect(find.text('Stored on this device'), findsOneWidget);
    await tester.tap(find.text('Change storage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Self-hosted server'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Server address'),
      'http://192.168.1.20:8080',
    );
    await tester.tap(find.text('Connect to server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch and sign out'));
    await tester.pumpAndSettle();
    expect(c.read(authProvider).value, isNull);
    expect(c.read(storageProvider).serverUrl, 'http://192.168.1.20:8080');
    expect(c.read(preferencesProvider).getString('demoUser'), isNull);
    expect(
      c.read(routerProvider).routeInformationProvider.value.uri.path,
      '/welcome',
    );
  });
  testWidgets('Live notification bar announces reminders as they come due', (
    tester,
  ) async {
    final c = await boot(tester, live: true);
    final store = c.read(localStoreProvider);
    final data = (await store.read())!;
    final today = c.read(todayProvider);
    final template = data.items.firstWhere(
      (i) => i.organisationId == 'realoffice' && !i.isClosed,
    );
    await store.write(
      data.copyWith(
        items: [
          ...data.items,
          template.patch({
            'id': 'fresh',
            'title': 'Fire NOC Renewal',
            'status': DueStatus.upcoming.name,
            'dueDate': today.add(const Duration(days: 1)).toIso8601String(),
          }),
        ],
      ),
    );
    await c.read(liveUpdatesProvider).tick();
    await tester.pumpAndSettle();
    final banner = find.byKey(const ValueKey('live-banner'));
    expect(banner.hitTestable(), findsOneWidget);
    expect(find.text('Fire NOC Renewal: 1 day left.'), findsWidgets);
    await tester.tap(banner);
    await tester.pumpAndSettle();
    expect(
      c
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .matches
          .last
          .matchedLocation,
      '/due/fresh',
    );
    expect(
      c
          .read(notificationsProvider)
          .firstWhere((n) => n.dueItemId == 'fresh')
          .read,
      isTrue,
    );
    // Quiet when nothing new arrives, and when banners are switched off.
    await c.read(settingsProvider.notifier).toggle('banner', false);
    await c.read(liveUpdatesProvider).tick();
    await tester.pump(const Duration(seconds: 6));
    expect(banner.hitTestable(), findsNothing);
  });
  testWidgets('Notification centre filters unread and marks items read', (
    tester,
  ) async {
    final c = await boot(tester);
    c.read(routerProvider).push('/notifications');
    await tester.pumpAndSettle();
    final unread = c.read(notificationsProvider).where((n) => !n.read).length;
    expect(unread, greaterThan(0));
    await tester.tap(find.text('Unread ($unread)'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    await tester.tap(find.text('Read all'));
    await tester.pumpAndSettle();
    expect(find.text('You’re all caught up.'), findsOneWidget);
    expect(c.read(notificationsProvider).every((n) => n.read), isTrue);
  });
  testWidgets('App lock: set a passcode, lock, reject wrong and accept right', (
    tester,
  ) async {
    final c = await boot(tester);
    Future<void> enter(String code) async {
      for (final d in code.split('')) {
        await tester.tap(
          find.descendant(
            of: find.byType(PasscodeKeypad),
            matching: find.text(d),
          ),
        );
        await tester.pump();
      }
      // Passcode hashing runs real asynchronous work.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
    }

    c.read(routerProvider).go('/settings/security');
    await tester.pumpAndSettle();
    expect(find.text('Require passcode'), findsOneWidget);
    await tester.tap(find.text('Require passcode'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a new passcode'), findsOneWidget);
    await enter('123456');
    expect(
      find.text('Choose a passcode that is harder to guess.'),
      findsOneWidget,
    );
    await enter('135792');
    expect(find.text('Confirm your passcode'), findsOneWidget);
    await enter('135792');
    expect(c.read(appLockProvider).enabled, isTrue);
    expect(find.text('Lock now'), findsOneWidget);

    await tester.tap(find.text('Lock now'));
    await tester.pumpAndSettle();
    expect(find.text('DueDesk is locked'), findsOneWidget);
    await enter('000000');
    expect(find.text('Wrong passcode. Try again.'), findsOneWidget);
    await enter('135792');
    expect(find.text('DueDesk is locked'), findsNothing);
    expect(find.text('Security'), findsWidgets);
  });
  testWidgets('App switcher shows a privacy shield instead of content', (
    tester,
  ) async {
    await boot(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(PrivacyShield), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(PrivacyShield), findsNothing);
  });
  testWidgets('Capture key screens for visual inspection', (tester) async {
    final c = await boot(tester);
    for (final (route, mode, filename) in [
      ('/home', ThemeMode.dark, 'dashboard-dark'),
      ('/home', ThemeMode.light, 'dashboard-light'),
      ('/due/gst', ThemeMode.dark, 'due-detail-dark'),
      ('/calendar', ThemeMode.light, 'calendar-light'),
      ('/due', ThemeMode.light, 'obligations-light'),
      ('/due?filter=Pinned', ThemeMode.dark, 'empty-pins-dark'),
      ('/due/new?templates=true', ThemeMode.light, 'templates-light'),
      ('/settings/storage', ThemeMode.light, 'storage-light'),
      ('/notifications', ThemeMode.light, 'notifications-light'),
      ('/settings/security', ThemeMode.dark, 'security-dark'),
      ('/settings/security/passcode', ThemeMode.light, 'passcode-light'),
    ]) {
      await c.read(themeProvider.notifier).set(mode);
      c.read(routerProvider).go(route);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (captureKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('artifacts').create();
        await File(
          'artifacts/$filename.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), null);
    }
  });
}
