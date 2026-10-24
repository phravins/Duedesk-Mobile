import 'package:flutter_test/flutter_test.dart';
import 'package:duedesk/features/compliance/domain/compliance_calendar.dart';
import 'package:duedesk/features/due_items/data/demo_seed.dart';
import 'package:duedesk/shared/models/models.dart';

ComplianceRule rule(String key) => ComplianceCalendar.packs
    .expand((p) => p.rules)
    .firstWhere((r) => r.key == key);

void main() {
  group('Statutory dates', () {
    test('monthly dates fall on or after today', () {
      final gstr1 = rule('gstr1');
      expect(
        gstr1.nextDue(DateTime.utc(2026, 10, 5)),
        DateTime.utc(2026, 10, 11),
      );
      expect(
        gstr1.nextDue(DateTime.utc(2026, 10, 11)),
        DateTime.utc(2026, 10, 11),
      );
      expect(
        gstr1.nextDue(DateTime.utc(2026, 10, 12)),
        DateTime.utc(2026, 11, 11),
      );
      expect(
        gstr1.nextDue(DateTime.utc(2026, 12, 20)),
        DateTime.utc(2027, 1, 11),
      );
    });

    test('month-end rules use the last day of short months', () {
      final pt = rule('pt');
      expect(pt.nextDue(DateTime.utc(2027, 2, 3)), DateTime.utc(2027, 2, 28));
      expect(pt.nextDue(DateTime.utc(2028, 2, 3)), DateTime.utc(2028, 2, 29));
      expect(pt.nextDue(DateTime.utc(2026, 4, 30)), DateTime.utc(2026, 4, 30));
    });

    test('yearly dates roll into next year once passed', () {
      final advance = rule('advance-4');
      expect(
        advance.nextDue(DateTime.utc(2026, 10, 24)),
        DateTime.utc(2027, 3, 15),
      );
      final q2 = rule('tds-q2');
      expect(
        q2.nextDue(DateTime.utc(2026, 10, 24)),
        DateTime.utc(2026, 10, 31),
      );
      expect(q2.nextDue(DateTime.utc(2026, 11, 1)), DateTime.utc(2027, 10, 31));
    });
  });

  group('Planning', () {
    final seed = demoSeed(now: DateTime.utc(2026, 10, 24));
    final org = seed.organisations.firstWhere((o) => o.id == 'realoffice');
    final owner = seed.users.firstWhere((u) => u.id == 'management');

    test('recognises obligations already tracked under other names', () {
      expect(rule('gstr3b').matches('GSTR-3B Filing'), isTrue);
      expect(rule('pt').matches('Professional Tax Payment'), isTrue);
      expect(rule('esi').matches('ESI contribution – October'), isTrue);
      expect(rule('esi').matches('Residential lease renewal'), isFalse);
      expect(rule('pf').matches('Office PF ledger'), isTrue);
      expect(rule('pf').matches('Pfizer contract'), isFalse);
    });

    test('creates recurring, owned, reminded obligations without repeats', () {
      final items = ComplianceCalendar.plan(
        packIds: {'gst', 'payroll'},
        organisation: org,
        categories: seed.categories,
        existing: seed.items,
        owner: owner,
        creator: owner,
        today: DateTime.utc(2026, 10, 24),
        reminderDays: const [3, 7, 0],
        id: () => 'id-${DateTime.now().microsecondsSinceEpoch}',
      );
      final titles = items.map((i) => i.title).toList();
      // GSTR-3B and professional tax are already in the demo workspace.
      expect(titles, isNot(contains('GSTR-3B return and GST payment')));
      expect(titles, isNot(contains('Professional tax payment')));
      expect(
        titles,
        containsAll(['GSTR-1 (outward supplies)', 'PF contribution (ECR)']),
      );
      final gstr1 = items.firstWhere((i) => i.title.startsWith('GSTR-1'));
      expect(gstr1.frequency, Frequency.monthly);
      expect(gstr1.dueDate, DateTime.utc(2026, 11, 11));
      expect(gstr1.assignedToUserId, owner.id);
      expect(gstr1.authority, 'GST Portal');
      expect(gstr1.categoryName, 'GST');
      expect(gstr1.reminderConfiguration.daysBefore, [7, 3, 0]);
      for (var i = 1; i < items.length; i++) {
        expect(items[i].dueDate.isBefore(items[i - 1].dueDate), isFalse);
      }
    });

    test('reports categories the organisation still needs', () {
      final missing = ComplianceCalendar.missingCategories(
        {'gst', 'payroll'},
        org.id,
        seed.categories.where((c) => c.name != 'HR').toList(),
      );
      expect(missing, {'HR'});
    });
  });
}
