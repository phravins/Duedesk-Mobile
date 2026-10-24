import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/utils/due_dates.dart';
import '../../../shared/models/models.dart';

/// Reports for accountants and auditors, and a calendar file, built from
/// the obligations of one organisation.
abstract final class Exports {
  static String _status(DueItem i, DateTime today) =>
      DueDates.status(i, today).label;

  static String _date(DateTime? d) =>
      d == null ? '' : DateFormat('yyyy-MM-dd').format(d);

  /// Spreadsheet-friendly CSV (RFC 4180), one row per obligation.
  static String csv(Iterable<DueItem> items, DateTime today) {
    String cell(Object? v) {
      final text = '${v ?? ''}';
      // Leading =, +, - or @ would be run as a formula by spreadsheets.
      final safe = RegExp(r'^[=+\-@]').hasMatch(text) ? "'$text" : text;
      return '"${safe.replaceAll('"', '""')}"';
    }

    final rows = [
      [
        'Title',
        'Category',
        'Due date',
        'Status',
        'Priority',
        'Frequency',
        'Owner',
        'Authority',
        'Reference',
        'Amount',
        'Currency',
        'Completed on',
        'Completed by',
        'Documents',
      ],
      for (final i
          in items.toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate)))
        [
          i.title,
          i.categoryName,
          _date(i.dueDate),
          _status(i, today),
          i.priority.label,
          i.frequency.label,
          i.assignedToName,
          i.authority,
          i.referenceNumber,
          i.amount?.toStringAsFixed(2) ?? '',
          i.amount == null ? '' : i.currency,
          _date(i.completionDate),
          i.completedBy ?? '',
          i.documentCount,
        ],
    ];
    return '${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n';
  }

  /// An iCalendar file of open obligations as all-day events that repeat
  /// like the obligation and carry its reminders as alerts.
  static String ics(
    Iterable<DueItem> items,
    Organisation organisation, {
    DateTime? now,
  }) {
    String text(String v) => v
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll('\n', '\\n');
    String fold(String line) {
      // Lines over 75 octets continue on the next line after a space.
      final bytes = utf8.encode(line);
      if (bytes.length <= 75) return line;
      final out = StringBuffer();
      var count = 0;
      for (final rune in line.runes) {
        final char = String.fromCharCode(rune);
        final size = utf8.encode(char).length;
        if (count + size > 75) {
          out.write('\r\n ');
          count = 1;
        }
        out.write(char);
        count += size;
      }
      return out.toString();
    }

    final stamp = DateFormat(
      "yyyyMMdd'T'HHmmss'Z'",
    ).format((now ?? DateTime.now()).toUtc());
    String day(DateTime d) => DateFormat('yyyyMMdd').format(d);
    String? rule(DueItem i) => switch (i.frequency) {
      Frequency.oneTime => null,
      Frequency.weekly => 'FREQ=WEEKLY',
      Frequency.monthly =>
        // A month-end schedule stays on the last day of each month.
        i.dueDate.day >= 28 &&
                DateTime.utc(i.dueDate.year, i.dueDate.month + 1, 0).day ==
                    i.dueDate.day
            ? 'FREQ=MONTHLY;BYMONTHDAY=-1'
            : 'FREQ=MONTHLY',
      Frequency.quarterly => 'FREQ=MONTHLY;INTERVAL=3',
      Frequency.halfYearly => 'FREQ=MONTHLY;INTERVAL=6',
      Frequency.yearly => 'FREQ=YEARLY',
      Frequency.custom =>
        int.tryParse(i.recurrenceRule ?? '') == null
            ? null
            : 'FREQ=DAILY;INTERVAL=${i.recurrenceRule}',
    };
    final lines = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//DueDesk//Compliance calendar//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${text('DueDesk – ${organisation.name}')}',
      for (final i in items)
        if (!i.isClosed) ...[
          'BEGIN:VEVENT',
          'UID:${i.id}@duedesk.app',
          'DTSTAMP:$stamp',
          'DTSTART;VALUE=DATE:${day(i.dueDate)}',
          'DTEND;VALUE=DATE:${day(i.dueDate.add(const Duration(days: 1)))}',
          'SUMMARY:${text(i.title)}',
          'DESCRIPTION:${text([if (i.description.isNotEmpty) i.description, 'Owner: ${i.assignedToName}', if (i.authority.isNotEmpty) 'Authority: ${i.authority}', if (i.referenceNumber.isNotEmpty) 'Reference: ${i.referenceNumber}'].join('\n'))}',
          'CATEGORIES:${text(i.categoryName)}',
          if (rule(i) case final r?) 'RRULE:$r',
          if (i.reminderConfiguration.enabled)
            for (final d in i.reminderConfiguration.daysBefore.toSet()) ...[
              'BEGIN:VALARM',
              'ACTION:DISPLAY',
              'DESCRIPTION:${text(i.title)}',
              // 9 AM on the day, or 9 AM the given number of days before.
              'TRIGGER:${d == 0 ? 'PT9H' : '-P${d - 1}DT15H'}',
              'END:VALARM',
            ],
          'END:VEVENT',
        ],
      'END:VCALENDAR',
    ];
    return '${lines.map(fold).join('\r\n')}\r\n';
  }

  /// A printable compliance report: summary counts, then every obligation
  /// grouped by where it stands.
  static Future<Uint8List> pdf({
    required Iterable<DueItem> items,
    required Organisation organisation,
    required DateTime today,
    required String preparedBy,
    required ByteData bodyFont,
    required ByteData headingFont,
    DateTime? now,
  }) async {
    final body = pw.Font.ttf(bodyFont), heading = pw.Font.ttf(headingFont);
    const ink = PdfColor.fromInt(0xFF141413),
        muted = PdfColor.fromInt(0xFF6B6A63),
        clay = PdfColor.fromInt(0xFFC6613F),
        line = PdfColor.fromInt(0xFFE5E3D8),
        paper = PdfColor.fromInt(0xFFF5F4EE);
    final list = items.toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final groups = <String, List<DueItem>>{
      'Overdue': [],
      'Due today': [],
      'Due soon': [],
      'In progress': [],
      'Upcoming': [],
      'Completed': [],
    };
    for (final i in list) {
      if (i.status == DueStatus.archived) continue;
      final key = switch (DueDates.status(i, today)) {
        DueStatus.overdue => 'Overdue',
        DueStatus.dueToday => 'Due today',
        DueStatus.dueSoon => 'Due soon',
        DueStatus.inProgress => 'In progress',
        DueStatus.completed || DueStatus.renewed => 'Completed',
        _ => 'Upcoming',
      };
      groups[key]!.add(i);
    }
    final generated = DateFormat(
      'd MMM yyyy, h:mm a',
    ).format((now ?? DateTime.now()).toLocal());
    final doc = pw.Document(
      title: 'Compliance report – ${organisation.name}',
      author: 'DueDesk',
    );
    final style = pw.TextStyle(font: body, fontSize: 9.5, color: ink);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
        theme: pw.ThemeData.withFont(base: body, bold: body),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'DueDesk · ${organisation.name}',
              style: style.copyWith(color: muted, fontSize: 8),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: style.copyWith(color: muted, fontSize: 8),
            ),
          ],
        ),
        build: (context) => [
          pw.Text(
            'Compliance report',
            style: pw.TextStyle(font: heading, fontSize: 22, color: ink),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${organisation.name} · as of ${DueDates.format(today, year: true)} · prepared by $preparedBy · generated $generated',
            style: style.copyWith(color: muted),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              for (final entry in groups.entries)
                pw.Expanded(
                  child: pw.Container(
                    margin: const pw.EdgeInsets.only(right: 6),
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: paper,
                      border: pw.Border.all(color: line),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '${entry.value.length}',
                          style: pw.TextStyle(
                            font: heading,
                            fontSize: 16,
                            color:
                                entry.key == 'Overdue' && entry.value.isNotEmpty
                                ? clay
                                : ink,
                          ),
                        ),
                        pw.Text(
                          entry.key,
                          style: style.copyWith(color: muted, fontSize: 8),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          for (final entry in groups.entries)
            if (entry.value.isNotEmpty) ...[
              pw.SizedBox(height: 18),
              pw.Text(
                entry.key,
                style: pw.TextStyle(font: heading, fontSize: 13, color: ink),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: [
                  'Obligation',
                  'Category',
                  'Due',
                  'Owner',
                  'Authority / reference',
                  entry.key == 'Completed' ? 'Completed' : 'Evidence',
                ],
                data: [
                  for (final i in entry.value)
                    [
                      i.title,
                      i.categoryName,
                      DueDates.format(i.dueDate, year: true),
                      i.assignedToName,
                      [
                        i.authority,
                        i.referenceNumber,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      entry.key == 'Completed'
                          ? [
                              if (i.completionDate != null)
                                DueDates.format(i.completionDate!, year: true),
                              if (i.completedBy != null) i.completedBy!,
                            ].join(' · ')
                          : '${i.documentCount} file${i.documentCount == 1 ? '' : 's'}',
                    ],
                ],
                headerStyle: style.copyWith(color: muted, fontSize: 8.5),
                headerDecoration: const pw.BoxDecoration(color: paper),
                cellStyle: style,
                border: pw.TableBorder(
                  horizontalInside: const pw.BorderSide(color: line, width: .5),
                  bottom: const pw.BorderSide(color: line, width: .5),
                ),
                cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 4,
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1.4),
                  2: const pw.FlexColumnWidth(1.4),
                  3: const pw.FlexColumnWidth(1.5),
                  4: const pw.FlexColumnWidth(2),
                  5: const pw.FlexColumnWidth(1.4),
                },
              ),
            ],
          pw.SizedBox(height: 18),
          pw.Text(
            'Generated from DueDesk records. Statutory submissions and acknowledgements remain with the respective authorities.',
            style: style.copyWith(color: muted, fontSize: 8),
          ),
        ],
      ),
    );
    return doc.save();
  }
}
