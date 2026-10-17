import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../data.dart';
import '../../domain.dart';
import '../planning/planning_domain.dart';

/// The caller explicitly supplies private rows; shared rows alone are the default.
class MonthlyReport {
  MonthlyReport(
    this.home,
    this.month,
    this.entries,
    this.items,
    this.payments, {
    required this.asOf,
    this.cached = false,
  });
  final Household home;
  final DateTime month, asOf;
  final List<FinanceEntry> entries;
  final Map<String, List<ExpenseItem>> items;
  final List<Repayment> payments;
  final bool cached;
  Map<String, List<List<Object>>> get sheets {
    final settlement = financeSettlement(
      home.members,
      home.legacyMembers,
      entries.where((e) => !e.personal),
      payments,
    );
    List<List<Object>> expenses(bool personal) => [
      [
        'ID',
        'Date',
        'Merchant',
        'Payer',
        'Category',
        'Currency',
        'Amount',
        'Kind',
        'Voided',
        'Split cents',
      ],
      for (final e in entries.where((e) => e.personal == personal))
        [
          e.id,
          e.date.toIso8601String().split('T').first,
          e.merchant,
          home.name(e.payer),
          e.category,
          home.currency,
          e.signedAmount / 100,
          e.refund ? 'Refund' : 'Expense',
          e.voided ? 'Yes' : 'No',
          e.splits == null ? 'Equal' : jsonEncode(e.splits),
        ],
    ];
    List<List<Object>> lineItems(bool personal) => [
      ['Expense ID', 'Item', 'Currency', 'Amount', 'Quantity', 'Unit'],
      for (final e in entries.where((e) => e.personal == personal))
        for (final i
            in items['${e.personal ? 'private' : 'shared'}/${e.id}'] ??
                <ExpenseItem>[])
          [
            e.id,
            i.name,
            home.currency,
            i.amount / 100,
            i.quantityMilli == null ? '' : i.quantityMilli! / 1000,
            i.unit ?? '',
          ],
    ];
    return {
      'Report': [
        ['Group', home.title],
        ['Group ID', home.id],
        ['Month', month.toIso8601String().substring(0, 7)],
        ['Generated UTC', asOf.toUtc().toIso8601String()],
        ['Source', cached ? 'Cached; may be incomplete' : 'Server snapshot'],
        ['Currency', home.currency],
        ['Shared net spending', settlement.total / 100],
        [
          'Note',
          'Refunds subtract; voided and personal expenses excluded from shared balances. Repayments are transfers, not spending.',
        ],
      ],
      'Shared expenses': expenses(false),
      'Shared items': lineItems(false),
      'Transfers': [
        [
          'ID',
          'Date',
          'From',
          'To',
          'Currency',
          'Amount',
          'Reversal of',
          'Reference',
        ],
        for (final p in payments)
          [
            p.id,
            p.date.toIso8601String().split('T').first,
            home.name(p.from),
            home.name(p.to),
            home.currency,
            p.signedAmount / 100,
            p.reversalOf,
            p.reference,
          ],
      ],
      'Settlement': [
        ['Person', 'Paid', 'Share', 'Balance after transfers'],
        for (final uid in settlement.paid.keys)
          [
            home.name(uid),
            settlement.paid[uid]! / 100,
            settlement.shares[uid]! / 100,
            settlement.transfers.fold<int>(
                  0,
                  (sum, t) =>
                      sum +
                      (t.creditor == uid ? t.amount : 0) -
                      (t.debtor == uid ? t.amount : 0),
                ) /
                100,
          ],
        ['Debtor', 'Creditor', 'Amount'],
        for (final t in settlement.transfers)
          [home.name(t.debtor), home.name(t.creditor), t.amount / 100],
      ],
      if (entries.any((e) => e.personal)) 'My private expenses': expenses(true),
      if (entries.any((e) => e.personal)) 'My private items': lineItems(true),
    };
  }

  Uint8List excel() => encodeWorkbook(sheets);
  Future<Uint8List> pdf(ByteData font) async {
    final document = pw.Document();
    final face = pw.Font.ttf(font);
    for (final sheet in sheets.entries) {
      document.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(base: face, bold: face),
          maxPages: 500,
          build: (_) => [
            pw.Header(level: 0, text: '${home.title} · ${sheet.key}'),
            pw.Text(
              '${month.toIso8601String().substring(0, 7)} · ${home.currency}',
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              data: sheet.value
                  .map(
                    (r) => r
                        .map((v) => v is double ? v.toStringAsFixed(2) : '$v')
                        .toList(),
                  )
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerStyle: const pw.TextStyle(fontSize: 8),
            ),
          ],
          footer: (c) => pw.Text(
            '${c.pageNumber}/${c.pagesCount} · ${asOf.toUtc().toIso8601String()}',
          ),
        ),
      );
    }
    return document.save();
  }
}

String _xml(Object value) => '$value'
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// OOXML inline strings keep merchant/item names (including = prefixes) as text.
Uint8List encodeWorkbook(Map<String, List<List<Object>>> sheets) {
  final archive = Archive();
  void add(String path, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  add(
    '[Content_Types].xml',
    '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${List.generate(sheets.length, (i) => '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join()}</Types>',
  );
  add(
    '_rels/.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  );
  add(
    'xl/workbook.xml',
    '<workbook xmlns="$ns" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${sheets.keys.indexed.map((e) => '<sheet name="${_xml(e.$2)}" sheetId="${e.$1 + 1}" r:id="rId${e.$1 + 1}"/>').join()}</sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${List.generate(sheets.length, (i) => '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>').join()}</Relationships>',
  );
  for (final sheet in sheets.values.indexed) {
    add(
      'xl/worksheets/sheet${sheet.$1 + 1}.xml',
      '<worksheet xmlns="$ns"><sheetData>${sheet.$2.map((row) => '<row>${row.map((v) => v is num ? '<c><v>$v</v></c>' : '<c t="inlineStr"><is><t xml:space="preserve">${_xml(v)}</t></is></c>').join()}</row>').join()}</sheetData></worksheet>',
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
