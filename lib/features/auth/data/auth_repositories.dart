import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api/api_client.dart';
import '../../../core/errors/failures.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/storage/local_store.dart';
import '../../../shared/models/models.dart';
import '../../due_items/data/demo_seed.dart';
import '../domain/auth_repository.dart';

class DemoAuthRepository implements AuthRepository {
  final SharedPreferences preferences;
  final LocalStore store;
  DemoAuthRepository(this.preferences, this.store);
  Future<WorkspaceData> _data() async {
    final d = await store.read();
    if (d != null) return d;
    final seed = demoSeed();
    await store.write(seed);
    return seed;
  }

  @override
  Future<User?> restore() async {
    final id = preferences.getString('demoUser');
    return id == null
        ? null
        : (await _data()).users.where((u) => u.id == id).firstOrNull;
  }

  @override
  Future<User> enterDemo() async {
    await preferences.setString('demoUser', 'management');
    return (await _data()).users.firstWhere((u) => u.id == 'management');
  }

  @override
  Future<User> signIn(
    String email,
    String password, {
    bool remember = true,
  }) async {
    final normalised = email.toLowerCase().trim();
    String? id;
    if (normalised == 'demo@duedesk.app' && password == 'demo123') {
      id = 'management';
    } else {
      final raw = preferences.getString('demo-account-$normalised');
      if (raw != null) {
        final record = jsonDecode(raw) as Map<String, dynamic>;
        final algorithm = Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: 210000,
          bits: 256,
        );
        final key = await algorithm.deriveKey(
          secretKey: SecretKey(utf8.encode(password)),
          nonce: base64Decode(record['salt']),
        );
        if (constantTimeEquals(
          await key.extractBytes(),
          base64Decode(record['verifier']),
        )) {
          id = record['id'];
        }
      }
    }
    if (id == null) {
      throw const AuthenticationFailure(
        'Email or password is incorrect. Demo access: demo@duedesk.app / demo123.',
      );
    }
    final user = (await _data()).users.where((u) => u.id == id).firstOrNull;
    if (user == null) throw const AuthenticationFailure();
    if (remember) {
      await preferences.setString('demoUser', id);
    } else {
      await preferences.remove('demoUser');
    }
    return user;
  }

  @override
  Future<User> register({
    required String name,
    required String email,
    required String password,
    required String phone,
  }) async {
    final d = await _data();
    final normalised = email.toLowerCase().trim();
    if (d.users.any((u) => u.email.toLowerCase() == normalised)) {
      throw const ValidationFailure(
        'An account with this email already exists.',
      );
    }
    final orgId = newId();
    final user = User(
      id: newId(),
      name: name,
      email: email,
      phone: phone,
      currentOrganisationId: orgId,
      memberships: {orgId: Role.owner},
    );
    await store.write(
      d.copyWith(
        users: [...d.users, user],
        organisations: [
          ...d.organisations,
          Organisation(
            id: orgId,
            name: "${name.split(' ').first}'s company",
            slug: orgId,
          ),
        ],
        categories: [
          ...d.categories,
          ...d.categories
              .where((c) => c.organisationId == 'realoffice')
              .map(
                (c) => DueCategory(
                  id: newId(),
                  name: c.name,
                  organisationId: orgId,
                ),
              ),
        ],
      ),
    );
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    );
    final salt = SecretKeyData.random(length: 16).bytes;
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    await preferences.setString(
      'demo-account-$normalised',
      jsonEncode({
        'id': user.id,
        'salt': base64Encode(salt),
        'verifier': base64Encode(await key.extractBytes()),
      }),
    );
    await preferences.setString('demoUser', user.id);
    await preferences.setString('organisation', orgId);
    return user;
  }

  @override
  Future<void> forgotPassword(String email) async {}
  @override
  Future<void> signOut() => preferences.remove('demoUser');
}

class ApiAuthRepository implements AuthRepository {
  final ApiClient api;
  ApiAuthRepository(this.api);
  @override
  Future<User?> restore() async {
    if (await api.tokens.access() == null) return null;
    try {
      return await api.guard(
        () async => User.fromJson(
          Map<String, dynamic>.from(
            (await api.dio.get('/users/me')).data['data'],
          ),
        ),
      );
    } on NetworkFailure {
      final profile = await api.tokens.profile();
      if (profile == null) rethrow;
      return User.fromJson(jsonDecode(profile) as Json);
    } on AuthenticationFailure {
      await api.tokens.clear();
      return null;
    }
  }

  Future<User> _authenticate(String path, Json data, {bool remember = true}) =>
      api.guard(() async {
        final r = await api.dio.post(
          path,
          data: data,
          options: Options(extra: {'public': true}),
        );
        await api.tokens.save(
          r.data['access_token'],
          r.data['refresh_token'],
          remember: remember,
        );
        final user = User.fromJson(Map<String, dynamic>.from(r.data['user']));
        await api.tokens.saveProfile(jsonEncode(user.toJson()));
        return user;
      });
  @override
  Future<User> signIn(String email, String password, {bool remember = true}) =>
      _authenticate('/auth/login', {
        'email': email,
        'password': password,
      }, remember: remember);
  @override
  Future<User> register({
    required String name,
    required String email,
    required String password,
    required String phone,
  }) => _authenticate('/auth/register', {
    'name': name,
    'email': email,
    'mobile_number': phone,
    'password': password,
  });
  @override
  Future<User> enterDemo() => throw const ValidationFailure(
    'Demo mode is available in APP_ENV=demo builds.',
  );
  @override
  Future<void> forgotPassword(String email) => api.guard(() async {
    await api.dio.post(
      '/auth/forgot-password',
      data: {'email': email},
      options: Options(extra: {'public': true}),
    );
  });
  @override
  Future<void> signOut() async {
    try {
      await api.dio.post('/auth/logout');
    } finally {
      await api.tokens.clear();
    }
  }
}
