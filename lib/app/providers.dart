import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api/api_client.dart';
import '../core/config/environment.dart';
import '../core/errors/failures.dart';
import '../core/security/app_lock.dart';
import '../core/storage/local_store.dart';
import '../core/storage/storage_settings.dart';
import '../core/utils/due_dates.dart';
import '../shared/models/models.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/data/auth_repositories.dart';
import '../features/due_items/domain/repositories.dart';
import '../features/due_items/data/mock_repository.dart';
import '../features/due_items/data/api_repository.dart';
import '../features/notifications/domain/notification_service.dart';

final preferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError('Bootstrap must supply this dependency.'),
);

/// The workspace folder on this device's drive.
final deviceStoreProvider = Provider<LocalStore>(
  (ref) => throw StateError('Bootstrap must supply this dependency.'),
);

/// Offline copy of what the self-hosted server last returned.
final serverCacheProvider = Provider<LocalStore>(
  (ref) => throw StateError('Bootstrap must supply this dependency.'),
);
final localStoreProvider = Provider<LocalStore>(
  (ref) => ref.watch(storageProvider).isDevice
      ? ref.watch(deviceStoreProvider)
      : ref.watch(serverCacheProvider),
);
final tokenStoreProvider = Provider<TokenStore>(
  (ref) => TokenStore(ref.watch(secureStorageProvider)),
);
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    ref.watch(tokenStoreProvider),
    baseUrl: ref.watch(storageProvider).serverUrl,
  );
  ref.onDispose(client.dio.close);
  return client;
});
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ref.watch(storageProvider).isDevice
      ? DemoAuthRepository(
          ref.watch(preferencesProvider),
          ref.watch(localStoreProvider),
        )
      : ApiAuthRepository(ref.watch(apiClientProvider)),
);
final repositoryProvider = Provider<WorkspaceRepository>(
  (ref) => ref.watch(storageProvider).isDevice
      ? MockDueItemRepository(ref.watch(localStoreProvider))
      : ApiDueItemRepository(
          ref.watch(apiClientProvider),
          ref.watch(localStoreProvider),
        ),
);

final storageProvider = NotifierProvider<StorageController, StorageSettings>(
  StorageController.new,
);

class StorageController extends Notifier<StorageSettings> {
  @override
  StorageSettings build() {
    final prefs = ref.watch(preferencesProvider);
    final saved = StorageMode.values
        .asNameMap()[prefs.getString('storageMode')];
    return StorageSettings(
      mode:
          saved ??
          (AppConfig.apiBaseUrl.isEmpty
              ? StorageMode.device
              : StorageMode.server),
      serverUrl: prefs.getString('serverUrl') ?? AppConfig.apiBaseUrl,
    );
  }

  /// Switches where the workspace is kept. Use [AuthController.switchStorage]
  /// so any current session ends first. Moving to a different server also
  /// drops the old server's tokens and offline copy.
  Future<void> change(StorageMode mode, {String? serverUrl}) async {
    final next = StorageSettings(
      mode: mode,
      serverUrl: serverUrl ?? state.serverUrl,
    );
    if (next.mode == state.mode && next.serverUrl == state.serverUrl) return;
    if (next.serverUrl != state.serverUrl) {
      await ref.read(tokenStoreProvider).clear();
      if (state.serverUrl.isNotEmpty) {
        await ref.read(serverCacheProvider).clear();
      }
    }
    final prefs = ref.read(preferencesProvider);
    await prefs.setString('storageMode', mode.name);
    if (next.serverUrl.isEmpty) {
      await prefs.remove('serverUrl');
    } else {
      await prefs.setString('serverUrl', next.serverUrl);
    }
    await prefs.remove('organisation');
    state = next;
    ref.invalidate(currentOrganisationProvider);
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = DemoNotificationService();
  ref.onDispose(service.dispose);
  return service;
});
final authProvider = AsyncNotifierProvider<AuthController, User?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<User?> {
  @override
  Future<User?> build() => ref.watch(authRepositoryProvider).restore();
  LoginThrottle get _throttle {
    final prefs = ref.read(preferencesProvider);
    return LoginThrottle(prefs.getString, prefs.setString, prefs.remove);
  }

  Future<void> login(String email, String password, bool remember) async {
    final throttle = _throttle;
    final wait = throttle.wait(email);
    if (wait != null) {
      throw ValidationFailure(
        'Too many attempts. For your security, try again in ${describeWait(wait)}.',
      );
    }
    final User u;
    try {
      u = await ref
          .read(authRepositoryProvider)
          .signIn(email, password, remember: remember);
    } on AuthenticationFailure {
      await throttle.failed(email);
      rethrow;
    }
    await throttle.succeeded(email);
    await _freshSession();
    state = AsyncData(u);
  }

  /// A password sign-in starts a new session, so any passcode left from an
  /// earlier one (for example a session that was not remembered) is dropped.
  Future<void> _freshSession() => ref.read(appLockProvider.notifier).disable();

  Future<void> demo() async {
    final u = await ref.read(authRepositoryProvider).enterDemo();
    await _freshSession();
    state = AsyncData(u);
  }

  Future<void> register(
    String name,
    String email,
    String password,
    String phone,
  ) async {
    final u = await ref
        .read(authRepositoryProvider)
        .register(name: name, email: email, password: password, phone: phone);
    ref
        .read(currentOrganisationProvider.notifier)
        .select(u.currentOrganisationId);
    await _freshSession();
    state = AsyncData(u);
  }

  /// Accounts on one store mean nothing on the other, so the current session
  /// is signed out before the app points at a different store.
  Future<void> switchStorage(StorageMode mode, {String? serverUrl}) async {
    if (state.value != null) {
      try {
        await logout();
      } catch (_) {}
    }
    await ref.read(storageProvider.notifier).change(mode, serverUrl: serverUrl);
  }

  Future<void> logout() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
    } finally {
      state = const AsyncData(null);
      ref.invalidate(workspaceProvider);
      // The app passcode belongs to this session, not to the device.
      await ref.read(appLockProvider.notifier).disable();
    }
  }
}

final currentOrganisationProvider =
    NotifierProvider<OrganisationController, String>(
      OrganisationController.new,
    );

class OrganisationController extends Notifier<String> {
  @override
  String build() =>
      ref.read(preferencesProvider).getString('organisation') ?? 'realoffice';
  Future<void> select(String id) async {
    state = id;
    await ref.read(preferencesProvider).setString('organisation', id);
  }
}

final workspaceProvider =
    AsyncNotifierProvider<WorkspaceController, WorkspaceData>(
      WorkspaceController.new,
    );

class WorkspaceController extends AsyncNotifier<WorkspaceData> {
  @override
  Future<WorkspaceData> build() async {
    final actor = await ref.watch(authProvider.future);
    if (actor == null) return const WorkspaceData();
    return ref.watch(repositoryProvider).load(actor);
  }

  Future<void> refresh() async {
    final actor = ref.read(authProvider).value;
    if (actor == null) return;
    final next = await ref.read(repositoryProvider).load(actor, refresh: true);
    state = AsyncData(next);
  }

  /// When this device last changed the workspace. Notifications that follow
  /// straight after are the person's own doing and are not announced.
  DateTime? lastLocalAction;

  Future<T> act<T>(
    Future<T> Function(WorkspaceRepository repository, User actor) action,
  ) async {
    lastLocalAction = DateTime.now();
    final identity = ref.read(authProvider).value;
    if (identity == null) throw const AuthenticationFailure();
    // Read our own snapshot, not a derived provider that depends on this notifier.
    final actor =
        state.value?.users.where((u) => u.id == identity.id).firstOrNull ??
        identity;
    final result = await action(ref.read(repositoryProvider), actor);
    await refresh();
    return result;
  }
}

final currentUserProvider = Provider<User>((ref) {
  final auth = ref.watch(authProvider).value;
  final data = ref.watch(workspaceProvider).value;
  return data?.users.where((u) => u.id == auth?.id).firstOrNull ??
      auth ??
      User(id: '', name: '', email: '', memberships: const {});
});
final organisationProvider = Provider<Organisation>((ref) {
  final d = ref.watch(workspaceProvider).value;
  final id = ref.watch(currentOrganisationProvider);
  return d?.organisations.where((o) => o.id == id).firstOrNull ??
      d?.organisations.firstOrNull ??
      const Organisation(
        id: 'realoffice',
        name: 'REALOFFICE',
        slug: 'realoffice',
      );
});
final todayProvider = Provider<DateTime>(
  (ref) => DueDates.today(ref.watch(organisationProvider).timezone),
);
final dueItemsProvider = Provider<List<DueItem>>((ref) {
  final org = ref.watch(organisationProvider);
  return ref
          .watch(workspaceProvider)
          .value
          ?.items
          .where((i) => i.organisationId == org.id)
          .toList() ??
      [];
});
final teamProvider = Provider<List<User>>((ref) {
  final org = ref.watch(organisationProvider);
  return ref
          .watch(workspaceProvider)
          .value
          ?.users
          .where((u) => u.memberships.containsKey(org.id))
          .toList() ??
      [];
});
final categoriesProvider = Provider<List<DueCategory>>((ref) {
  final org = ref.watch(organisationProvider);
  return ref
          .watch(workspaceProvider)
          .value
          ?.categories
          .where((c) => c.organisationId == org.id)
          .toList() ??
      [];
});
final documentsProvider = Provider<List<Document>>((ref) {
  final org = ref.watch(organisationProvider);
  return ref
          .watch(workspaceProvider)
          .value
          ?.documents
          .where((d) => d.organisationId == org.id)
          .toList() ??
      [];
});
final notificationsProvider = Provider<List<DueNotification>>((ref) {
  final org = ref.watch(organisationProvider);
  return ref
          .watch(workspaceProvider)
          .value
          ?.notifications
          .where((n) => n.organisationId == org.id)
          .toList() ??
      [];
});
final dueItemDetailProvider = Provider.family<DueItem?, String>(
  (ref, id) => ref.watch(dueItemsProvider).where((i) => i.id == id).firstOrNull,
);
final themeProvider = NotifierProvider<ThemeController, ThemeMode>(
  ThemeController.new,
);

class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.values.byName(
    ref.read(preferencesProvider).getString('theme') ?? 'system',
  );
  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(preferencesProvider).setString('theme', mode.name);
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, Map<String, bool>>(
      SettingsController.new,
    );

class SettingsController extends Notifier<Map<String, bool>> {
  static const defaults = {
    'push': true,
    'email': true,
    'assignment': true,
    'overdue': true,
    'completion': true,
    'banner': true,
    'reminder30': false,
    'reminder15': false,
    'reminder7': true,
    'reminder3': true,
    'reminder1': true,
    'reminder0': true,
  };
  @override
  Map<String, bool> build() => defaults.map(
    (k, v) => MapEntry(k, ref.read(preferencesProvider).getBool(k) ?? v),
  );
  Future<void> toggle(String key, bool value) async {
    state = {...state, key: value};
    await ref.read(preferencesProvider).setBool(key, value);
  }
}

final connectivityProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) async* {
  final c = Connectivity();
  yield await c.checkConnectivity();
  yield* c.onConnectivityChanged;
});

/// Personal shortcuts are isolated by account and organisation, never shared permissions.
final pinnedItemsProvider =
    NotifierProvider<PinnedItemsController, Set<String>>(
      PinnedItemsController.new,
    );

class PinnedItemsController extends Notifier<Set<String>> {
  String get _key =>
      'pins:${ref.read(currentUserProvider).id}:${ref.read(organisationProvider).id}';
  @override
  Set<String> build() {
    ref.watch(currentUserProvider);
    ref.watch(organisationProvider);
    return ref.read(preferencesProvider).getStringList(_key)?.toSet() ?? {};
  }

  Future<void> toggle(String id) async {
    final key = _key;
    final next = {...state};
    if (!next.add(id)) next.remove(id);
    final stored = await ref
        .read(preferencesProvider)
        .setStringList(key, next.toList());
    if (stored && ref.mounted && _key == key) state = next;
  }
}
