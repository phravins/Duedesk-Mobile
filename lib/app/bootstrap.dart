import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import '../core/config/environment.dart';
import '../core/storage/device_store.dart';
import '../core/security/app_lock.dart';
import '../core/storage/local_store.dart';
import '../core/storage/storage_cipher.dart';
import 'app.dart';
import 'providers.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    AppConfig.validate();
    tz.initializeTimeZones();
    await Hive.initFlutter();
    final prefs = await SharedPreferences.getInstance();
    final key = await loadStorageKey(secureStorage);
    final cache = await openServerCache(key);
    final device = await openDeviceStore(key);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    runApp(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          deviceStoreProvider.overrideWithValue(device),
          serverCacheProvider.overrideWithValue(cache),
        ],
        child: const DueDeskApp(),
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 48),
                    const SizedBox(height: 20),
                    const Text(
                      'DueDesk could not start.',
                      style: TextStyle(fontSize: 22),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Check the app configuration and available device storage, then try again.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: bootstrap,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The offline copy of server data, encrypted with the device storage key.
/// Copies kept unencrypted by earlier versions are only a cache, so they are
/// deleted rather than migrated; the next refresh fills the new one.
Future<HiveLocalStore> openServerCache(List<int> key) async {
  final env = AppConfig.environmentName;
  for (final legacy in ['$env-server-cache', '$env-server-files']) {
    if (await Hive.boxExists(legacy)) await Hive.deleteBoxFromDisk(legacy);
  }
  final cipher = HiveAesCipher(key);
  return HiveLocalStore(
    await Hive.openBox<String>(
      '$env-server-cache-v2',
      encryptionCipher: cipher,
    ),
    await Hive.openBox<List<int>>(
      '$env-server-files-v2',
      encryptionCipher: cipher,
    ),
  );
}
