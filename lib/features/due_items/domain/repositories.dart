import 'dart:typed_data';
import '../../../shared/models/models.dart';

class PageRequest {
  final int page, limit;
  final String? cursor;
  const PageRequest({this.page = 1, this.limit = 50, this.cursor});
  Json toJson() => {
    'page': page,
    'limit': limit,
    if (cursor != null) 'cursor': cursor,
  };
}

abstract interface class DueItemRepository {
  Future<List<DueItem>> getDueItems(
    User actor,
    String organisationId, {
    PageRequest page = const PageRequest(),
  });
  Future<DueItem> getDueItem(User actor, String id);
  Future<DueItem> createDueItem(User actor, DueItem item);
  Future<DueItem> updateDueItem(User actor, DueItem item);
  Future<void> startDueItem(User actor, String id);
  Future<void> setProgress(User actor, String id, DueStatus status);
  Future<void> addNote(User actor, String id, String note);
  Future<DueItem?> completeDueItem(
    User actor,
    String id, {
    required DateTime date,
    required String notes,
    required String reference,
    bool renew = true,
    DateTime? nextDate,
  });
  Future<DueItem?> renewDueItem(User actor, String id, {DateTime? nextDate});
  Future<void> archiveDueItem(User actor, String id);
}

abstract interface class DocumentRepository {
  Future<Document> uploadDocument(
    User actor,
    String itemId,
    String filename,
    Uint8List bytes, {
    String? replaceId,
    void Function(double)? onProgress,
  });
  Future<Uint8List> readDocument(User actor, Document document);
  Future<void> removeDocument(User actor, String id);
}

abstract interface class CompanyRepository {
  Future<void> saveCompany(User actor, Organisation organisation);
  Future<void> saveCategory(User actor, DueCategory category);
}

abstract interface class UserRepository {
  Future<void> inviteUser(
    User actor,
    String organisationId,
    String name,
    String email,
    Role role,
  );
  Future<void> updateMember(
    User actor,
    String organisationId,
    String id,
    Role role,
    bool active,
  );
  Future<void> saveProfile(User actor, User user);
}

abstract interface class NotificationRepository {
  Future<void> markRead(User actor, String organisationId, {String? id});

  /// Raises reminders that have become due for the organisation and returns
  /// how many were added. Servers schedule reminders themselves, so remote
  /// repositories return 0 and rely on refreshes to deliver them.
  Future<int> syncReminders(
    User actor,
    String organisationId,
    DateTime today, {
    bool overdueAlerts = true,
  });
}

abstract interface class WorkspaceRepository
    implements
        DueItemRepository,
        DocumentRepository,
        CompanyRepository,
        UserRepository,
        NotificationRepository {
  Future<WorkspaceData> load(User actor, {bool refresh = false});
}
