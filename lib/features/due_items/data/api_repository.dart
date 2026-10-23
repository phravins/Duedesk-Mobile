import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/errors/failures.dart';
import '../../../core/storage/local_store.dart';
import '../../../shared/models/models.dart';
import '../domain/repositories.dart';

// Phoenix contract: JSON records use the model keys; collections are wrapped in `data`.
// Completion/renewal endpoints must be transactional and enforce membership server-side.
class ApiDueItemRepository implements WorkspaceRepository {
  final ApiClient api;
  final LocalStore cache;
  bool showingCached = false;
  ApiDueItemRepository(this.api, this.cache);
  @override
  Future<WorkspaceData> load(User actor, {bool refresh = false}) async {
    try {
      final data = await api.guard(() async {
        final r = await api.dio.get('/workspace');
        return WorkspaceData.fromJson(
          Map<String, dynamic>.from(r.data['data']),
        );
      });
      await cache.write(data.copyWith(cachedForUserId: actor.id));
      showingCached = false;
      return data;
    } on NetworkFailure {
      final saved = await cache.read();
      if (saved == null || saved.cachedForUserId != actor.id) rethrow;
      showingCached = true;
      return saved;
    }
  }

  @override
  Future<List<DueItem>> getDueItems(
    User actor,
    String organisationId, {
    PageRequest page = const PageRequest(),
  }) => api.guard(() async {
    final r = await api.dio.get(
      '/organisations/$organisationId/due-items',
      queryParameters: page.toJson(),
    );
    return (r.data['data'] as List)
        .map((j) => DueItem.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  });
  @override
  Future<DueItem> getDueItem(User actor, String id) => api.guard(
    () async => DueItem.fromJson(
      Map<String, dynamic>.from(
        (await api.dio.get('/due-items/$id')).data['data'],
      ),
    ),
  );
  @override
  Future<DueItem> createDueItem(User actor, DueItem item) => api.guard(
    () async => DueItem.fromJson(
      Map<String, dynamic>.from(
        (await api.dio.post(
          '/organisations/${item.organisationId}/due-items',
          data: {'due_item': item.toJson()},
        )).data['data'],
      ),
    ),
  );
  @override
  Future<DueItem> updateDueItem(User actor, DueItem item) => api.guard(
    () async => DueItem.fromJson(
      Map<String, dynamic>.from(
        (await api.dio.patch(
          '/due-items/${item.id}',
          data: {'due_item': item.toJson()},
        )).data['data'],
      ),
    ),
  );
  Future<void> _post(String path, [Json? data]) => api.guard(() async {
    await api.dio.post(path, data: data);
  });
  @override
  Future<void> setProgress(User actor, String id, DueStatus status) =>
      _post('/due-items/$id/progress', {'status': status.name});
  @override
  Future<void> startDueItem(User actor, String id) =>
      _post('/due-items/$id/start');
  @override
  Future<void> addNote(User actor, String id, String note) =>
      _post('/due-items/$id/notes', {'text': note});
  @override
  Future<DueItem?> completeDueItem(
    User actor,
    String id, {
    required DateTime date,
    required String notes,
    required String reference,
    bool renew = true,
    DateTime? nextDate,
  }) => api.guard(() async {
    final r = await api.dio.post(
      '/due-items/$id/complete',
      data: {
        'completion_date': date.toIso8601String(),
        'notes': notes,
        'acknowledgement': reference,
        'renew': renew,
        'next_due_date': nextDate?.toIso8601String(),
      },
    );
    return r.data['next_due_item'] == null
        ? null
        : DueItem.fromJson(Map<String, dynamic>.from(r.data['next_due_item']));
  });
  @override
  Future<DueItem?> renewDueItem(User actor, String id, {DateTime? nextDate}) =>
      api.guard(() async {
        final r = await api.dio.post(
          '/due-items/$id/renew',
          data: {'next_due_date': nextDate?.toIso8601String()},
        );
        return DueItem.fromJson(Map<String, dynamic>.from(r.data['data']));
      });
  @override
  Future<void> archiveDueItem(User actor, String id) =>
      _post('/due-items/$id/archive');
  @override
  Future<Document> uploadDocument(
    User actor,
    String itemId,
    String filename,
    Uint8List bytes, {
    String? replaceId,
    void Function(double)? onProgress,
  }) => api.guard(() async {
    final r = await api.dio.post(
      '/due-items/$itemId/documents',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
        'replace_id': ?replaceId,
      }),
      onSendProgress: (sent, total) =>
          onProgress?.call(total == 0 ? 0 : sent / total),
    );
    return Document.fromJson(Map<String, dynamic>.from(r.data['data']));
  });
  @override
  Future<Uint8List> readDocument(User actor, Document document) =>
      api.guard(() async {
        final r = await api.dio.get<List<int>>(
          '/documents/${document.id}/download',
          options: Options(responseType: ResponseType.bytes),
        );
        return Uint8List.fromList(r.data!);
      });
  @override
  Future<void> removeDocument(User actor, String id) => api.guard(() async {
    await api.dio.delete('/documents/$id');
  });
  @override
  Future<void> saveCompany(User actor, Organisation organisation) =>
      api.guard(() async {
        await api.dio.patch(
          '/organisations/${organisation.id}',
          data: {'organisation': organisation.toJson()},
        );
      });
  @override
  Future<void> saveCategory(User actor, DueCategory category) =>
      api.guard(() async {
        await api.dio.put(
          '/organisations/${category.organisationId}/categories/${category.id}',
          data: {'category': category.toJson()},
        );
      });
  @override
  Future<void> inviteUser(
    User actor,
    String organisationId,
    String name,
    String email,
    Role role,
  ) => _post('/organisations/$organisationId/invitations', {
    'name': name,
    'email': email,
    'role': role.name,
  });
  @override
  Future<void> updateMember(
    User actor,
    String organisationId,
    String id,
    Role role,
    bool active,
  ) => api.guard(() async {
    await api.dio.patch(
      '/organisations/$organisationId/members/$id',
      data: {'role': role.name, 'active': active},
    );
  });
  @override
  Future<void> saveProfile(User actor, User user) => api.guard(() async {
    await api.dio.patch(
      '/users/me',
      data: {
        'name': user.name,
        'phone': user.phone,
        'avatarUrl': user.avatarUrl,
      },
    );
  });
  @override
  Future<void> markRead(User actor, String organisationId, {String? id}) =>
      _post('/organisations/$organisationId/notifications/read', {'id': id});
  @override
  Future<int> syncReminders(
    User actor,
    String organisationId,
    DateTime today, {
    bool overdueAlerts = true,
  }) async => 0;
}
