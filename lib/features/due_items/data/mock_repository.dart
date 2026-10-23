import 'dart:async';
import 'package:flutter/services.dart';
import '../../../shared/models/models.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/due_dates.dart';
import '../../../core/utils/permissions.dart';
import '../domain/repositories.dart';
import '../../notifications/domain/reminders.dart';
import 'demo_seed.dart';

class MockDueItemRepository implements WorkspaceRepository {
  final LocalStore store;
  Future<void> _tail = Future.value();
  MockDueItemRepository(this.store);
  Future<WorkspaceData> _read() async {
    final data = await store.read();
    if (data != null) return data;
    final seed = demoSeed();
    await store.write(seed);
    return seed;
  }

  // Serialise read-modify-write operations so simultaneous actions cannot lose history.
  Future<T> _mutate<T>(
    Future<(WorkspaceData, T)> Function(WorkspaceData) action,
  ) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        final (data, value) = await action(await _read());
        await store.write(data);
        result.complete(value);
      } catch (e, st) {
        result.completeError(e, st);
      }
    });
    return result.future;
  }

  User _actor(WorkspaceData data, User actor) => data.users.firstWhere(
    (u) => u.id == actor.id,
    orElse: () => throw const AuthenticationFailure(),
  );
  DueItem _item(WorkspaceData data, String id) => data.items.firstWhere(
    (i) => i.id == id,
    orElse: () =>
        throw const ValidationFailure('This DueItem is no longer available.'),
  );
  ActivityEvent _event(
    User actor,
    DueItem item,
    String type,
    String description, {
    Json metadata = const {},
  }) => ActivityEvent(
    id: newId(),
    organisationId: item.organisationId,
    dueItemId: item.id,
    type: type,
    description: description,
    actor: actor.name,
    timestamp: DateTime.now(),
    metadata: metadata,
  );
  WorkspaceData _replace(WorkspaceData d, DueItem item, ActivityEvent event) =>
      d.copyWith(
        items: [
          for (final i in d.items)
            if (i.id == item.id) item else i,
        ],
        activities: [event, ...d.activities],
        notifications: [
          if ([
            'status_changed',
            'completed',
            'renewed',
            'document_uploaded',
            'reassigned',
          ].contains(event.type))
            DueNotification(
              id: newId(),
              organisationId: item.organisationId,
              dueItemId: item.id,
              type: event.type,
              message: '${item.title}: ${event.description}',
              timestamp: event.timestamp,
            ),
          ...d.notifications,
        ],
      );
  void _validate(WorkspaceData d, DueItem item) {
    if (item.title.trim().isEmpty) {
      throw const ValidationFailure('Enter a title.');
    }
    if (!d.categories.any(
      (c) => c.id == item.categoryId && c.organisationId == item.organisationId,
    )) {
      throw const ValidationFailure('Select a category in this organisation.');
    }
    if (!d.users.any(
      (u) =>
          u.id == item.assignedToUserId &&
          u.roleIn(item.organisationId) != null,
    )) {
      throw const ValidationFailure('Select an active team member.');
    }
    if (item.startDate != null &&
        DueDates.date(item.startDate!).isAfter(DueDates.date(item.dueDate))) {
      throw const ValidationFailure(
        'Start date must be on or before the due date.',
      );
    }
    if (item.amount != null && (!item.amount!.isFinite || item.amount! < 0)) {
      throw const ValidationFailure('Enter a valid positive amount.');
    }
    if (item.frequency == Frequency.custom) DueDates.next(item);
  }

  @override
  Future<WorkspaceData> load(User actor, {bool refresh = false}) async {
    await _tail;
    final d = await _read(), a = _actor(await _read(), actor);
    final visible = d.items.where((i) => Permissions.view(a, i)).toList();
    final ids = visible.map((i) => i.id).toSet();
    return d.copyWith(
      organisations: d.organisations
          .where((o) => a.roleIn(o.id) != null)
          .toList(),
      items: visible,
      documents: d.documents.where((v) => ids.contains(v.dueItemId)).toList(),
      activities: d.activities.where((v) => ids.contains(v.dueItemId)).toList(),
      notifications: d.notifications
          .where((v) => ids.contains(v.dueItemId))
          .toList(),
      users: d.users
          .where(
            (u) =>
                u.id == a.id ||
                u.memberships.keys.any(a.memberships.containsKey),
          )
          .toList(),
      categories: d.categories
          .where((c) => a.roleIn(c.organisationId) != null)
          .toList(),
    );
  }

  @override
  Future<List<DueItem>> getDueItems(
    User actor,
    String organisationId, {
    PageRequest page = const PageRequest(),
  }) async => (await load(actor)).items
      .where((i) => i.organisationId == organisationId)
      .skip((page.page - 1) * page.limit)
      .take(page.limit)
      .toList();
  @override
  Future<DueItem> getDueItem(User actor, String id) async {
    final d = await _read(), item = _item(await _read(), id);
    Permissions.require(Permissions.view(_actor(d, actor), item));
    return item;
  }

  @override
  Future<DueItem> createDueItem(User actor, DueItem item) => _mutate((d) async {
    final a = _actor(d, actor);
    Permissions.require(Permissions.manage(a, item.organisationId));
    _validate(d, item);
    if (d.items.any((i) => i.id == item.id)) {
      throw const ValidationFailure('This DueItem already exists.');
    }
    final created = item.patch({
      'status': 'upcoming',
      'createdByUserId': a.id,
      'documentCount': 0,
      'completionDate': null,
      'completedBy': null,
      'archivedAt': null,
      'nextDueDate': null,
    });
    return (
      d.copyWith(
        items: [created, ...d.items],
        activities: [
          _event(
            a,
            created,
            'created',
            'Created and assigned to ${created.assignedToName}',
          ),
          ...d.activities,
        ],
      ),
      created,
    );
  });
  @override
  Future<DueItem> updateDueItem(User actor, DueItem item) => _mutate((d) async {
    final old = _item(d, item.id), a = _actor(d, actor);
    Permissions.require(
      Permissions.manage(a, old.organisationId) &&
          !old.isClosed &&
          old.organisationId == item.organisationId,
    );
    _validate(d, item);
    final updated = item.patch({
      'status': old.status.name,
      'createdByUserId': old.createdByUserId,
      'createdAt': old.createdAt.toIso8601String(),
      'documentCount': old.documentCount,
      'completionDate': null,
      'completedBy': null,
      'archivedAt': null,
      'nextDueDate': null,
    });
    return (
      _replace(
        d,
        updated,
        _event(
          a,
          updated,
          old.assignedToUserId == updated.assignedToUserId
              ? 'updated'
              : 'reassigned',
          old.assignedToUserId == updated.assignedToUserId
              ? 'Updated obligation details'
              : 'Reassigned to ${updated.assignedToName}',
        ),
      ),
      updated,
    );
  });
  @override
  Future<void> startDueItem(User actor, String id) =>
      setProgress(actor, id, DueStatus.inProgress);
  @override
  Future<void> setProgress(User actor, String id, DueStatus status) =>
      _mutate<void>((d) async {
        final i = _item(d, id), a = _actor(d, actor);
        Permissions.require(Permissions.update(a, i));
        if (![DueStatus.upcoming, DueStatus.inProgress].contains(status)) {
          throw const ValidationFailure(
            'Use the completion flow to record a completed obligation.',
          );
        }
        return (
          _replace(
            d,
            i.patch({'status': status.name}),
            _event(
              a,
              i,
              'status_changed',
              status == DueStatus.inProgress
                  ? 'Work started'
                  : 'Reset progress to upcoming',
            ),
          ),
          null,
        );
      });
  @override
  Future<void> addNote(User actor, String id, String note) => _mutate<void>((
    d,
  ) async {
    final i = _item(d, id), a = _actor(d, actor);
    Permissions.require(Permissions.view(a, i));
    if (note.trim().isEmpty) throw const ValidationFailure('Enter a note.');
    return (
      d.copyWith(
        activities: [_event(a, i, 'note_added', note.trim()), ...d.activities],
      ),
      null,
    );
  });
  DueItem _next(DueItem item, User actor, DateTime next) => item.patch({
    'id': newId(),
    'dueDate': next.toIso8601String(),
    'startDate': null,
    'status': 'upcoming',
    'completionDate': null,
    'completedBy': null,
    'nextDueDate': null,
    'archivedAt': null,
    'documentCount': 0,
    'notes': '',
    'createdAt': DateTime.now().toIso8601String(),
    'createdByUserId': actor.id,
  });
  @override
  Future<DueItem?> completeDueItem(
    User actor,
    String id, {
    required DateTime date,
    required String notes,
    required String reference,
    bool renew = true,
    DateTime? nextDate,
  }) => _mutate((d) async {
    final i = _item(d, id), a = _actor(d, actor);
    Permissions.require(Permissions.update(a, i));
    final org = d.organisations.firstWhere((o) => o.id == i.organisationId);
    if (DueDates.date(date).isAfter(DueDates.today(org.timezone))) {
      throw const ValidationFailure('Completion date cannot be in the future.');
    }
    final next = renew ? (nextDate ?? DueDates.next(i)) : null;
    if (next != null &&
        !DueDates.date(next).isAfter(DueDates.date(i.dueDate))) {
      throw const ValidationFailure(
        'The next due date must be after this obligation.',
      );
    }
    final child = next == null ? null : _next(i, a, next);
    final completed = i.patch({
      'status': child == null ? 'completed' : 'renewed',
      'completionDate': date.toIso8601String(),
      'completedBy': a.name,
      'nextDueDate': next?.toIso8601String(),
    });
    var updated = _replace(
      d,
      completed,
      _event(
        a,
        i,
        'completed',
        notes.trim().isEmpty ? 'Marked as completed' : notes.trim(),
        metadata: {
          'completionDate': date.toIso8601String(),
          'acknowledgement': reference,
        },
      ),
    );
    if (child != null) {
      updated = updated.copyWith(
        items: [child, ...updated.items],
        activities: [
          _event(
            a,
            i,
            'renewed',
            'Next obligation created for ${DueDates.format(next!, year: true)}',
            metadata: {'nextItemId': child.id},
          ),
          _event(
            a,
            child,
            'created',
            'Renewed from ${i.title}',
            metadata: {'previousItemId': i.id},
          ),
          ...updated.activities,
        ],
      );
    }
    return (updated, child);
  });
  @override
  Future<DueItem?> renewDueItem(User actor, String id, {DateTime? nextDate}) =>
      _mutate((d) async {
        final i = _item(d, id), a = _actor(d, actor);
        Permissions.require(Permissions.view(a, i));
        if (i.status != DueStatus.completed || i.nextDueDate != null) {
          throw const ValidationFailure(
            'This obligation cannot be renewed again.',
          );
        }
        final next = nextDate ?? DueDates.next(i);
        if (next == null) {
          throw const ValidationFailure('This is a one-time obligation.');
        }
        if (!DueDates.date(next).isAfter(DueDates.date(i.dueDate))) {
          throw const ValidationFailure('Choose a later due date.');
        }
        final child = _next(i, a, next);
        final updated = _replace(
          d,
          i.patch({'status': 'renewed', 'nextDueDate': next.toIso8601String()}),
          _event(
            a,
            i,
            'renewed',
            'Created next obligation',
            metadata: {'nextItemId': child.id},
          ),
        );
        return (
          updated.copyWith(
            items: [child, ...updated.items],
            activities: [
              _event(a, child, 'created', 'Renewed from ${i.title}'),
              ...updated.activities,
            ],
          ),
          child,
        );
      });
  @override
  Future<void> archiveDueItem(User actor, String id) =>
      _mutate<void>((d) async {
        final i = _item(d, id), a = _actor(d, actor);
        Permissions.require(Permissions.manage(a, i.organisationId));
        return (
          _replace(
            d,
            i.patch({
              'status': 'archived',
              'archivedAt': DateTime.now().toIso8601String(),
            }),
            _event(a, i, 'archived', 'Archived; history retained'),
          ),
          null,
        );
      });
  @override
  Future<Document> uploadDocument(
    User actor,
    String itemId,
    String filename,
    Uint8List bytes, {
    String? replaceId,
    void Function(double)? onProgress,
  }) => _mutate((d) async {
    final i = _item(d, itemId), a = _actor(d, actor);
    Permissions.require(
      Permissions.view(a, i) && i.status != DueStatus.archived,
    );
    if (replaceId != null && i.isClosed) {
      throw const PermissionFailure(
        'Completed evidence is retained. Add a new document instead.',
      );
    }
    final ext = filename.split('.').last.toLowerCase();
    const mime = {
      'pdf': 'application/pdf',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'txt': 'text/plain',
    };
    if (!mime.containsKey(ext)) {
      throw const ValidationFailure(
        'Use PDF, PNG, JPG, DOC, DOCX, or TXT files.',
      );
    }
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const ValidationFailure('Files must be between 1 byte and 20 MB.');
    }
    if (ext == 'pdf' &&
        (bytes.length < 4 || String.fromCharCodes(bytes.take(4)) != '%PDF')) {
      throw const ValidationFailure('This file is not a valid PDF.');
    }
    if (replaceId != null &&
        !d.documents.any((v) => v.id == replaceId && v.dueItemId == i.id)) {
      throw const ValidationFailure('Document not found.');
    }
    final id = newId();
    onProgress?.call(.3);
    await store.putFile(id, bytes);
    onProgress?.call(1);
    final doc = Document(
      id: id,
      organisationId: i.organisationId,
      dueItemId: i.id,
      filename: filename.split(RegExp(r'[/\\]')).last,
      fileType: ext,
      fileSize: bytes.length,
      mimeType: mime[ext]!,
      url: 'local:$id',
      uploadedBy: a.name,
      uploadedAt: DateTime.now(),
    );
    final docs = [doc, ...d.documents.where((v) => v.id != replaceId)];
    final updated = _replace(
      d.copyWith(documents: docs),
      i.patch({'documentCount': docs.where((v) => v.dueItemId == i.id).length}),
      _event(
        a,
        i,
        'document_uploaded',
        '${replaceId == null ? 'Uploaded' : 'Replaced'} ${doc.filename}',
      ),
    );
    // Retain replaced bytes until snapshot commits; orphan cleanup is safe to defer.
    return (updated, doc);
  });
  @override
  Future<Uint8List> readDocument(User actor, Document document) async {
    final d = await _read();
    final actual = d.documents.firstWhere(
      (v) => v.id == document.id,
      orElse: () => throw const ValidationFailure('Document not found.'),
    );
    Permissions.require(
      Permissions.view(_actor(d, actor), _item(d, actual.dueItemId)),
    );
    if (actual.url.startsWith('asset:')) {
      return (await rootBundle.load(
        actual.url.substring(6),
      )).buffer.asUint8List();
    }
    final bytes = await store.getFile(actual.id);
    if (bytes == null) {
      throw const ValidationFailure(
        'The document is unavailable on this device.',
      );
    }
    return bytes;
  }

  @override
  Future<void> removeDocument(User actor, String id) => _mutate<void>((
    d,
  ) async {
    final doc = d.documents.firstWhere(
      (v) => v.id == id,
      orElse: () => throw const ValidationFailure('Document not found.'),
    );
    final i = _item(d, doc.dueItemId), a = _actor(d, actor);
    Permissions.require(Permissions.manage(a, i.organisationId) && !i.isClosed);
    final docs = d.documents.where((v) => v.id != id).toList();
    return (
      _replace(
        d.copyWith(documents: docs),
        i.patch({
          'documentCount': docs.where((v) => v.dueItemId == i.id).length,
        }),
        _event(a, i, 'document_removed', 'Removed ${doc.filename}'),
      ),
      null,
    );
  });
  @override
  Future<void> saveCompany(User actor, Organisation organisation) =>
      _mutate<void>((d) async {
        Permissions.require(
          Permissions.manage(_actor(d, actor), organisation.id),
        );
        if (organisation.name.trim().isEmpty) {
          throw const ValidationFailure('Enter the company name.');
        }
        return (
          d.copyWith(
            organisations: [
              for (final o in d.organisations)
                if (o.id == organisation.id) organisation else o,
            ],
          ),
          null,
        );
      });
  @override
  Future<void> saveCategory(User actor, DueCategory category) =>
      _mutate<void>((d) async {
        Permissions.require(
          Permissions.manage(_actor(d, actor), category.organisationId),
        );
        if (category.name.trim().isEmpty) {
          throw const ValidationFailure('Enter a category name.');
        }
        if (d.categories.any(
          (c) =>
              c.organisationId == category.organisationId &&
              c.id != category.id &&
              c.name.toLowerCase() == category.name.toLowerCase(),
        )) {
          throw const ValidationFailure('This category already exists.');
        }
        return (
          d.copyWith(
            categories: [
              category,
              ...d.categories.where((c) => c.id != category.id),
            ],
            items: [
              for (final i in d.items)
                if (i.categoryId == category.id)
                  i.patch({'categoryName': category.name})
                else
                  i,
            ],
          ),
          null,
        );
      });
  @override
  Future<void> inviteUser(
    User actor,
    String organisationId,
    String name,
    String email,
    Role role,
  ) => _mutate<void>((d) async {
    final a = _actor(d, actor);
    Permissions.require(
      Permissions.manage(a, organisationId) &&
          (role != Role.owner || Permissions.owner(a, organisationId)),
    );
    if (!email.contains('@') || name.trim().isEmpty) {
      throw const ValidationFailure('Enter a name and valid email.');
    }
    if (d.users.any(
      (u) =>
          u.email.toLowerCase() == email.toLowerCase() &&
          u.memberships.containsKey(organisationId),
    )) {
      throw const ValidationFailure(
        'This member already belongs to the organisation.',
      );
    }
    final existing = d.users
        .where((u) => u.email.toLowerCase() == email.toLowerCase())
        .firstOrNull;
    final user =
        existing?.copyWith(
          memberships: {...existing.memberships, organisationId: role},
          membershipActive: {
            ...existing.membershipActive,
            organisationId: false,
          },
        ) ??
        User(
          id: newId(),
          name: name,
          email: email,
          status: 'invited',
          memberships: {organisationId: role},
        );
    return (
      d.copyWith(users: [user, ...d.users.where((u) => u.id != user.id)]),
      null,
    );
  });
  @override
  Future<void> updateMember(
    User actor,
    String organisationId,
    String id,
    Role role,
    bool active,
  ) => _mutate<void>((d) async {
    final a = _actor(d, actor), u = d.users.firstWhere((u) => u.id == id);
    Permissions.require(
      Permissions.manage(a, organisationId) &&
          u.memberships.containsKey(organisationId),
    );
    if ((role == Role.owner || u.memberships[organisationId] == Role.owner) &&
        !Permissions.owner(a, organisationId)) {
      throw const PermissionFailure('Only owners can manage owner roles.');
    }
    if (id == a.id) {
      throw const ValidationFailure(
        'Another owner must change your own access.',
      );
    }
    if (u.roleIn(organisationId) == Role.owner &&
        (role != Role.owner || !active) &&
        d.users.where((u) => u.roleIn(organisationId) == Role.owner).length <=
            1) {
      throw const ValidationFailure('Keep at least one active owner.');
    }
    final member = u.copyWith(
      memberships: {...u.memberships, organisationId: role},
      status: u.status == 'invited' && active ? 'active' : u.status,
      membershipActive: {...u.membershipActive, organisationId: active},
    );
    return (
      d.copyWith(
        users: [
          for (final v in d.users)
            if (v.id == id) member else v,
        ],
      ),
      null,
    );
  });
  @override
  Future<void> saveProfile(User actor, User user) => _mutate<void>((d) async {
    final a = _actor(d, actor);
    Permissions.require(a.id == user.id);
    if (user.name.trim().isEmpty) {
      throw const ValidationFailure('Enter your name.');
    }
    final updated = a.copyWith(
      name: user.name,
      phone: user.phone,
      avatarUrl: user.avatarUrl,
    );
    return (
      d.copyWith(
        users: [
          for (final u in d.users)
            if (u.id == a.id) updated else u,
        ],
        items: [
          for (final i in d.items)
            if (i.assignedToUserId == a.id)
              i.patch({'assignedToName': updated.name})
            else
              i,
        ],
      ),
      null,
    );
  });
  @override
  Future<void> markRead(User actor, String organisationId, {String? id}) =>
      _mutate<void>((d) async {
        final a = _actor(d, actor);
        Permissions.require(a.roleIn(organisationId) != null);
        final visible = d.items
            .where((i) => Permissions.view(a, i))
            .map((i) => i.id)
            .toSet();
        return (
          d.copyWith(
            notifications: [
              for (final n in d.notifications)
                if (n.organisationId == organisationId &&
                    visible.contains(n.dueItemId) &&
                    (id == null || n.id == id))
                  DueNotification.fromJson({...n.toJson(), 'read': true})
                else
                  n,
            ],
          ),
          null,
        );
      });
  @override
  Future<int> syncReminders(
    User actor,
    String organisationId,
    DateTime today, {
    bool overdueAlerts = true,
  }) async {
    List<DueNotification> owed(WorkspaceData d) {
      final a = _actor(d, actor);
      if (a.roleIn(organisationId) == null) return const [];
      return remindersDue(
        d.items.where(
          (i) => i.organisationId == organisationId && Permissions.view(a, i),
        ),
        d.notifications,
        today,
        overdueAlerts: overdueAlerts,
      );
    }

    // Checked first so a quiet minute does not rewrite the workspace file.
    await _tail;
    if (owed(await _read()).isEmpty) return 0;
    return _mutate<int>((d) async {
      final fresh = owed(d);
      return (
        d.copyWith(notifications: [...fresh, ...d.notifications]),
        fresh.length,
      );
    });
  }
}
