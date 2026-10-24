import '../../../core/utils/due_dates.dart';
import '../../../shared/models/models.dart';

/// One statutory obligation and when it next falls due.
class ComplianceRule {
  final String key, title, category, authority, description;
  final Frequency frequency;
  final Priority priority;

  /// Day of the month the obligation is due. With [month] set it is a
  /// yearly date; otherwise it repeats every month. 31 means the last day.
  final int day;
  final int? month;

  /// Other names people give this obligation, so one already tracked under
  /// a different title is not added twice.
  final List<String> aliases;
  const ComplianceRule({
    required this.key,
    required this.title,
    required this.category,
    required this.authority,
    required this.description,
    required this.day,
    this.month,
    this.frequency = Frequency.monthly,
    this.priority = Priority.high,
    this.aliases = const [],
  });

  /// Whether an obligation titled [title] already covers this rule.
  bool matches(String title) {
    final text = title.toLowerCase();
    if (text == this.title.toLowerCase()) return true;
    return aliases.any(
      (a) => RegExp(
        '(^|[^a-z0-9])${RegExp.escape(a)}(\$|[^a-z0-9])',
      ).hasMatch(text),
    );
  }

  /// The first due date on or after [today] (a civil date).
  DateTime nextDue(DateTime today) {
    final t = DueDates.date(today);
    DateTime on(int year, int month) {
      final last = DateTime.utc(year, month + 1, 0).day;
      return DateTime.utc(year, month, day > last ? last : day);
    }

    if (month != null) {
      final thisYear = on(t.year, month!);
      return thisYear.isBefore(t) ? on(t.year + 1, month!) : thisYear;
    }
    final thisMonth = on(t.year, t.month);
    return thisMonth.isBefore(t) ? on(t.year, t.month + 1) : thisMonth;
  }
}

/// A set of obligations that apply together, chosen with one switch.
class CompliancePack {
  final String id, title, subtitle;
  final List<ComplianceRule> rules;
  const CompliancePack(this.id, this.title, this.subtitle, this.rules);
}

/// Common Indian statutory deadlines for a small business.
///
/// Dates are the usual statutory dates; the government often extends them,
/// and some (professional tax, quarterly GST filing) depend on the state or
/// scheme. People confirm them before relying on them.
abstract final class ComplianceCalendar {
  static const packs = [
    CompliancePack('gst', 'GST', 'Monthly returns and the annual return', [
      ComplianceRule(
        key: 'gstr1',
        aliases: ['gstr-1', 'gstr1'],
        title: 'GSTR-1 (outward supplies)',
        category: 'GST',
        authority: 'GST Portal',
        day: 11,
        description:
            'Monthly statement of outward supplies for the previous month. Quarterly (QRMP) filers use IFF instead; adjust if that applies to you.',
      ),
      ComplianceRule(
        key: 'gstr3b',
        aliases: ['gstr-3b', 'gstr3b'],
        title: 'GSTR-3B return and GST payment',
        category: 'GST',
        authority: 'GST Portal',
        day: 20,
        description:
            'Summary return and tax payment for the previous month. Attach the filing acknowledgement and challan.',
      ),
      ComplianceRule(
        key: 'gstr9',
        aliases: ['gstr-9', 'gstr9'],
        title: 'GSTR-9 annual return',
        category: 'GST',
        authority: 'GST Portal',
        day: 31,
        month: 12,
        frequency: Frequency.yearly,
        description: 'Annual GST return for the previous financial year.',
      ),
    ]),
    CompliancePack('tds', 'TDS', 'Monthly deposit and quarterly returns', [
      ComplianceRule(
        key: 'tds-deposit',
        aliases: ['tds deposit', 'tds payment', 'tcs deposit'],
        title: 'TDS / TCS deposit',
        category: 'Tax',
        authority: 'Income Tax Department',
        day: 7,
        description:
            'Deposit tax deducted or collected in the previous month. For March deductions the due date is 30 April.',
      ),
      ComplianceRule(
        key: 'tds-q1',
        title: 'TDS return Q1 (Apr–Jun)',
        category: 'Tax',
        authority: 'TRACES',
        day: 31,
        month: 7,
        frequency: Frequency.yearly,
        description: 'Quarterly TDS statements (24Q / 26Q) for April to June.',
      ),
      ComplianceRule(
        key: 'tds-q2',
        title: 'TDS return Q2 (Jul–Sep)',
        category: 'Tax',
        authority: 'TRACES',
        day: 31,
        month: 10,
        frequency: Frequency.yearly,
        description:
            'Quarterly TDS statements (24Q / 26Q) for July to September.',
      ),
      ComplianceRule(
        key: 'tds-q3',
        title: 'TDS return Q3 (Oct–Dec)',
        category: 'Tax',
        authority: 'TRACES',
        day: 31,
        month: 1,
        frequency: Frequency.yearly,
        description:
            'Quarterly TDS statements (24Q / 26Q) for October to December.',
      ),
      ComplianceRule(
        key: 'tds-q4',
        title: 'TDS return Q4 (Jan–Mar)',
        category: 'Tax',
        authority: 'TRACES',
        day: 31,
        month: 5,
        frequency: Frequency.yearly,
        description:
            'Quarterly TDS statements (24Q / 26Q) for January to March.',
      ),
    ]),
    CompliancePack('advance-tax', 'Advance tax', 'Four instalments a year', [
      ComplianceRule(
        key: 'advance-1',
        title: 'Advance tax – 1st instalment (15%)',
        category: 'Tax',
        authority: 'Income Tax Department',
        day: 15,
        month: 6,
        frequency: Frequency.yearly,
        description: 'At least 15% of the estimated tax for the year.',
      ),
      ComplianceRule(
        key: 'advance-2',
        title: 'Advance tax – 2nd instalment (45%)',
        category: 'Tax',
        authority: 'Income Tax Department',
        day: 15,
        month: 9,
        frequency: Frequency.yearly,
        description: 'At least 45% of the estimated tax, cumulatively.',
      ),
      ComplianceRule(
        key: 'advance-3',
        title: 'Advance tax – 3rd instalment (75%)',
        category: 'Tax',
        authority: 'Income Tax Department',
        day: 15,
        month: 12,
        frequency: Frequency.yearly,
        description: 'At least 75% of the estimated tax, cumulatively.',
      ),
      ComplianceRule(
        key: 'advance-4',
        title: 'Advance tax – 4th instalment (100%)',
        category: 'Tax',
        authority: 'Income Tax Department',
        day: 15,
        month: 3,
        frequency: Frequency.yearly,
        description: 'The full estimated tax for the year.',
      ),
    ]),
    CompliancePack('income-tax', 'Income tax return', 'Audited businesses', [
      ComplianceRule(
        key: 'itr',
        aliases: ['income tax return', 'itr'],
        title: 'Income tax return (audit cases)',
        category: 'Tax',
        authority: 'Income Tax Department',
        day: 31,
        month: 10,
        frequency: Frequency.yearly,
        description:
            'Return for businesses that need a tax audit. Non-audit returns are usually due on 31 July.',
      ),
    ]),
    CompliancePack('roc', 'Company (ROC)', 'Annual MCA filings', [
      ComplianceRule(
        key: 'dir3',
        aliases: ['dir-3', 'dir3'],
        title: 'DIR-3 KYC for directors',
        category: 'Statutory',
        authority: 'MCA',
        day: 30,
        month: 9,
        frequency: Frequency.yearly,
        description: 'Annual KYC for every director with a DIN.',
      ),
      ComplianceRule(
        key: 'aoc4',
        aliases: ['aoc-4', 'aoc4'],
        title: 'AOC-4 financial statements',
        category: 'Statutory',
        authority: 'MCA',
        day: 30,
        month: 10,
        frequency: Frequency.yearly,
        description:
            'Within 30 days of the AGM (shown for an AGM on 30 September).',
      ),
      ComplianceRule(
        key: 'mgt7',
        aliases: ['mgt-7', 'mgt7'],
        title: 'MGT-7 annual return',
        category: 'Statutory',
        authority: 'MCA',
        day: 29,
        month: 11,
        frequency: Frequency.yearly,
        description:
            'Within 60 days of the AGM (shown for an AGM on 30 September).',
      ),
    ]),
    CompliancePack('payroll', 'Payroll', 'PF, ESI and professional tax', [
      ComplianceRule(
        key: 'pf',
        aliases: ['pf', 'provident fund', 'epf'],
        title: 'PF contribution (ECR)',
        category: 'HR',
        authority: 'EPFO',
        day: 15,
        description: 'Employee and employer PF for the previous month.',
      ),
      ComplianceRule(
        key: 'esi',
        aliases: ['esi', 'esic'],
        title: 'ESI contribution',
        category: 'HR',
        authority: 'ESIC',
        day: 15,
        description: 'ESI contributions for the previous month.',
      ),
      ComplianceRule(
        key: 'pt',
        aliases: ['professional tax'],
        title: 'Professional tax payment',
        category: 'Tax',
        authority: 'State tax department',
        day: 31,
        priority: Priority.medium,
        description:
            'Due dates and frequency vary by state. Shown as month end; change it to match your state.',
      ),
    ]),
  ];

  static Iterable<ComplianceRule> rulesFor(Set<String> packIds) => [
    for (final pack in packs)
      if (packIds.contains(pack.id)) ...pack.rules,
  ];

  /// Obligations to create for an organisation: one per rule, skipping any
  /// already open there (by title or a known alias), so running the setup
  /// again is safe.
  static List<DueItem> plan({
    required Set<String> packIds,
    required Organisation organisation,
    required List<DueCategory> categories,
    required List<DueItem> existing,
    required User owner,
    required User creator,
    required DateTime today,
    List<int> reminderDays = const [7, 3, 1, 0],
    DateTime? now,
    String Function()? id,
  }) {
    final open = [
      for (final i in existing)
        if (i.organisationId == organisation.id && !i.isClosed) i.title,
    ];
    final stamp = now ?? DateTime.now();
    final items = <DueItem>[];
    for (final rule in rulesFor(packIds)) {
      if (open.any(rule.matches)) continue;
      final category = categories.firstWhere(
        (c) =>
            c.organisationId == organisation.id &&
            c.name.toLowerCase() == rule.category.toLowerCase(),
        orElse: () => DueCategory(
          id: 'missing-${rule.category}',
          organisationId: organisation.id,
          name: rule.category,
        ),
      );
      items.add(
        DueItem(
          id: id?.call() ?? newId(),
          organisationId: organisation.id,
          title: rule.title,
          description: rule.description,
          categoryId: category.id,
          categoryName: category.name,
          dueDate: rule.nextDue(today),
          frequency: rule.frequency,
          priority: rule.priority,
          authority: rule.authority,
          assignedToUserId: owner.id,
          assignedToName: owner.name,
          createdByUserId: creator.id,
          reminderConfiguration: ReminderConfiguration(
            enabled: reminderDays.isNotEmpty,
            daysBefore: [...reminderDays]..sort((a, b) => b.compareTo(a)),
          ),
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
    }
    items.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return items;
  }

  /// Category names the plan needs that the organisation does not have yet.
  static Set<String> missingCategories(
    Set<String> packIds,
    String organisationId,
    List<DueCategory> categories,
  ) {
    final have = {
      for (final c in categories)
        if (c.organisationId == organisationId && c.active)
          c.name.toLowerCase(),
    };
    return {
      for (final r in rulesFor(packIds))
        if (!have.contains(r.category.toLowerCase())) r.category,
    };
  }
}
