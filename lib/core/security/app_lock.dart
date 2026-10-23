import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../../app/providers.dart';

/// Keychain items stay on this device: they are not restored to another
/// phone from a backup, and are readable once the device has been unlocked.
const secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  mOptions: MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => secureStorage,
);

/// Face ID, Touch ID or the platform equivalent. Missing hardware, missing
/// enrolment and unsupported platforms all read as "not available".
class BiometricAuth {
  final LocalAuthentication _auth;
  BiometricAuth([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  Future<bool> available() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported() &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }
}

final biometricAuthProvider = Provider<BiometricAuth>((ref) => BiometricAuth());

/// Salted PBKDF2 verifier for the app passcode. The passcode itself is never
/// stored.
class PasscodeHasher {
  final int iterations;
  const PasscodeHasher({this.iterations = 120000});
  Pbkdf2 get _algorithm =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);

  Future<String> create(String passcode) async {
    final salt = SecretKeyData.random(length: 16).bytes;
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(passcode)),
      nonce: salt,
    );
    return jsonEncode({
      'v': 1,
      'iterations': iterations,
      'salt': base64Encode(salt),
      'verifier': base64Encode(await key.extractBytes()),
    });
  }

  Future<bool> verify(String passcode, String record) async {
    final data = jsonDecode(record) as Map<String, dynamic>;
    final key =
        await Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: data['iterations'] as int? ?? iterations,
          bits: 256,
        ).deriveKey(
          secretKey: SecretKey(utf8.encode(passcode)),
          nonce: base64Decode(data['salt'] as String),
        );
    return constantTimeEquals(
      await key.extractBytes(),
      base64Decode(data['verifier'] as String),
    );
  }
}

/// Compares secrets without leaking, through timing, where they differ.
bool constantTimeEquals(List<int> a, List<int> b) {
  var diff = a.length ^ b.length;
  for (var i = 0; i < a.length && i < b.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

final passcodeHasherProvider = Provider<PasscodeHasher>(
  (ref) => const PasscodeHasher(),
);

@immutable
class AppLockState {
  /// False until the Keychain has been read at start-up.
  final bool ready;
  final bool enabled;
  final bool locked;
  final bool biometrics;
  final bool privacyShield;

  /// How long the app may sit in the background before it locks again.
  final Duration timeout;
  final int failures;
  final DateTime? blockedUntil;
  const AppLockState({
    this.ready = false,
    this.enabled = false,
    this.locked = false,
    this.biometrics = false,
    this.privacyShield = true,
    this.timeout = const Duration(minutes: 1),
    this.failures = 0,
    this.blockedUntil,
  });
  AppLockState copyWith({
    bool? ready,
    bool? enabled,
    bool? locked,
    bool? biometrics,
    bool? privacyShield,
    Duration? timeout,
    int? failures,
    DateTime? blockedUntil,
    bool clearBlock = false,
  }) => AppLockState(
    ready: ready ?? this.ready,
    enabled: enabled ?? this.enabled,
    locked: locked ?? this.locked,
    biometrics: biometrics ?? this.biometrics,
    privacyShield: privacyShield ?? this.privacyShield,
    timeout: timeout ?? this.timeout,
    failures: failures ?? this.failures,
    blockedUntil: clearBlock ? null : blockedUntil ?? this.blockedUntil,
  );
}

enum UnlockResult { unlocked, wrong, blocked, signedOut }

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);

/// A passcode (and optional Face ID / Touch ID) between the device and the
/// workspace. Wrong guesses back off exponentially; ten in a row sign the
/// account out, so the password is needed again.
class AppLockController extends Notifier<AppLockState> {
  static const passcodeLength = 6;
  static const maxAttempts = 10;
  static const _pinKey = 'app_lock_passcode';
  static const _failuresKey = 'app_lock_failures';
  static const timeouts = [
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];
  DateTime? _backgroundedAt;

  /// Overridable clock for tests.
  DateTime Function() now = DateTime.now;

  FlutterSecureStorage get _storage => ref.read(secureStorageProvider);

  @override
  AppLockState build() {
    final prefs = ref.read(preferencesProvider);
    Future.microtask(_load);
    return AppLockState(
      biometrics: prefs.getBool('lockBiometrics') ?? false,
      privacyShield: prefs.getBool('privacyShield') ?? true,
      // A minute's grace lets people pick a file or photo without relocking.
      timeout: Duration(seconds: prefs.getInt('lockTimeout') ?? 60),
    );
  }

  Future<void> _load() async {
    String? pin, failures;
    try {
      pin = await _storage.read(key: _pinKey);
      failures = await _storage.read(key: _failuresKey);
    } catch (_) {}
    if (!ref.mounted) return;
    final count = int.tryParse(failures ?? '') ?? 0;
    state = state.copyWith(
      ready: true,
      enabled: pin != null,
      // A cold start always asks for the passcode.
      locked: pin != null,
      failures: count,
      blockedUntil: _blockFor(count),
    );
  }

  DateTime? _blockFor(int failures) => failures < 5
      ? null
      : now().add(Duration(seconds: 30 * (1 << (failures - 5).clamp(0, 5))));

  Future<void> setPasscode(String passcode) async {
    if (!RegExp('^\\d{$passcodeLength}\$').hasMatch(passcode)) {
      throw ArgumentError('Passcode must be $passcodeLength digits.');
    }
    final record = await ref.read(passcodeHasherProvider).create(passcode);
    await _storage.write(key: _pinKey, value: record);
    await _storage.delete(key: _failuresKey);
    state = state.copyWith(
      ready: true,
      enabled: true,
      locked: false,
      failures: 0,
      clearBlock: true,
    );
  }

  /// Removes the passcode. Also used when the account signs out, so the next
  /// person to sign in on this device chooses their own.
  Future<void> disable() async {
    try {
      await _storage.delete(key: _pinKey);
      await _storage.delete(key: _failuresKey);
    } catch (_) {}
    await setBiometrics(false);
    state = state.copyWith(
      enabled: false,
      locked: false,
      failures: 0,
      clearBlock: true,
    );
  }

  Future<UnlockResult> unlock(String passcode) async {
    final blocked = state.blockedUntil;
    if (blocked != null && now().isBefore(blocked)) return UnlockResult.blocked;
    final record = await _storage.read(key: _pinKey);
    if (record == null) {
      state = state.copyWith(enabled: false, locked: false);
      return UnlockResult.unlocked;
    }
    if (await ref.read(passcodeHasherProvider).verify(passcode, record)) {
      await _storage.delete(key: _failuresKey);
      state = state.copyWith(locked: false, failures: 0, clearBlock: true);
      return UnlockResult.unlocked;
    }
    final failures = state.failures + 1;
    if (failures >= maxAttempts) {
      await signOut();
      return UnlockResult.signedOut;
    }
    await _storage.write(key: _failuresKey, value: '$failures');
    state = state.copyWith(
      failures: failures,
      blockedUntil: _blockFor(failures),
      clearBlock: failures < 5,
    );
    return UnlockResult.wrong;
  }

  Future<bool> unlockWithBiometrics() async {
    if (!state.enabled || !state.biometrics) return false;
    final ok = await ref
        .read(biometricAuthProvider)
        .authenticate('Unlock your DueDesk workspace');
    if (ok && ref.mounted) {
      await _storage.delete(key: _failuresKey);
      state = state.copyWith(locked: false, failures: 0, clearBlock: true);
    }
    return ok;
  }

  /// Ends the session and forgets the passcode; the password is needed next.
  Future<void> signOut() async {
    await disable();
    try {
      await ref.read(authProvider.notifier).logout();
    } catch (_) {}
  }

  void lock() {
    if (state.enabled) state = state.copyWith(locked: true);
  }

  void backgrounded() => _backgroundedAt ??= now();

  void foregrounded() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since != null &&
        state.enabled &&
        now().difference(since) >= state.timeout) {
      lock();
    }
  }

  Future<void> setBiometrics(bool value) async {
    await ref.read(preferencesProvider).setBool('lockBiometrics', value);
    if (ref.mounted) state = state.copyWith(biometrics: value);
  }

  Future<void> setTimeout(Duration value) async {
    await ref.read(preferencesProvider).setInt('lockTimeout', value.inSeconds);
    state = state.copyWith(timeout: value);
  }

  Future<void> setPrivacyShield(bool value) async {
    await ref.read(preferencesProvider).setBool('privacyShield', value);
    state = state.copyWith(privacyShield: value);
  }
}

/// True while the app is inactive or in the app switcher.
final appObscuredProvider = NotifierProvider<AppObscuredController, bool>(
  AppObscuredController.new,
);

class AppObscuredController extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

/// Spaces sign-in attempts out after repeated failures, per email address.
/// The server enforces its own limits; this keeps a device from being used
/// to guess quickly.
class LoginThrottle {
  static const freeAttempts = 5;
  final Future<void> Function(String key, String value) _write;
  final String? Function(String key) _read;
  final Future<void> Function(String key) _remove;
  final DateTime Function() now;
  LoginThrottle(
    this._read,
    this._write,
    this._remove, {
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  String _key(String email) => 'login-throttle:${email.toLowerCase().trim()}';

  ({int failures, DateTime? last}) _record(String email) {
    final raw = _read(_key(email));
    if (raw == null) return (failures: 0, last: null);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return (
      failures: data['failures'] as int? ?? 0,
      last: DateTime.tryParse(data['last'] as String? ?? ''),
    );
  }

  /// How long to wait before the next attempt, or null when one is allowed.
  Duration? wait(String email) {
    final r = _record(email);
    if (r.failures < freeAttempts || r.last == null) return null;
    final delay = Duration(
      seconds: 30 * (1 << (r.failures - freeAttempts).clamp(0, 5)),
    );
    final remaining = r.last!.add(delay).difference(now());
    return remaining > Duration.zero ? remaining : null;
  }

  Future<void> failed(String email) => _write(
    _key(email),
    jsonEncode({
      'failures': _record(email).failures + 1,
      'last': now().toUtc().toIso8601String(),
    }),
  );

  Future<void> succeeded(String email) => _remove(_key(email));
}

String describeWait(Duration wait) {
  final seconds = wait.inSeconds + 1;
  if (seconds < 60) return '$seconds seconds';
  final minutes = (seconds / 60).ceil();
  return minutes == 1 ? '1 minute' : '$minutes minutes';
}
