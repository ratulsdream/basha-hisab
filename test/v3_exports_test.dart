import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:basha_hisab/data.dart';
import 'package:basha_hisab/domain.dart';
import 'package:basha_hisab/features/exports/report.dart';
import 'package:basha_hisab/features/planning/planning_domain.dart';

void main() {
  final home = Household('home', {
    'memberIds': ['a', 'b'],
    'memberNames': {'a': 'Αλέξης', 'b': 'Bob'},
    'currency': 'EUR',
    'inviteCode': 'x',
  });
  final report = MonthlyReport(
    home,
    DateTime(2026, 10),
    [
      FinanceEntry(
        id: '1',
        merchant: 'ΣΥΝΟΛΟ & <shop>',
        payer: 'a',
        date: DateTime(2026, 10, 1),
        amount: 1250,
      ),
    ],
    {
      'shared/1': [const ExpenseItem('=HYPERLINK("bad")', 1250)],
    },
    [],
    asOf: DateTime.utc(2026, 10, 17),
  );
  test('Excel contains Greek, escapes XML and treats formulas as strings', () {
    final zip = ZipDecoder().decodeBytes(report.excel());
    final contents = zip.files
        .map((f) => utf8.decode(f.content as List<int>))
        .join();
    expect(contents, contains('ΣΥΝΟΛΟ &amp; &lt;shop&gt;'));
    expect(contents, contains('=HYPERLINK(&quot;bad&quot;)'));
    expect(contents, contains('t="inlineStr"'));
    expect(contents, isNot(contains('<f>')));
    expect(report.sheets.keys, isNot(contains('My private expenses')));
    expect(report.sheets['Report']!.any((r) => r.contains(12.5)), true);
  });
  test('PDF embeds local font and creates a valid document offline', () async {
    final bytes = await report.pdf(
      ByteData.sublistView(
        await File('assets/fonts/DejaVuSans.ttf').readAsBytes(),
      ),
    );
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(10000));
  });
  test('private item namespaces stay separate and transfers are not costs', () {
    final scoped = MonthlyReport(
      home,
      DateTime(2026, 10),
      [
        FinanceEntry(
          id: 'same',
          merchant: 'Shared',
          payer: 'a',
          date: DateTime(2026, 10, 1),
          amount: 1250,
        ),
        FinanceEntry(
          id: 'refund',
          merchant: 'Refund',
          payer: 'a',
          date: DateTime(2026, 10, 2),
          amount: 250,
          refund: true,
        ),
        FinanceEntry(
          id: 'same',
          merchant: 'Secret',
          payer: 'a',
          date: DateTime(2026, 10, 1),
          amount: 9999,
          personal: true,
        ),
      ],
      {
        'shared/same': [const ExpenseItem('Milk', 1250)],
        'private/same': [const ExpenseItem('Secret item', 9999)],
      },
      [
        Repayment(
          id: 'p',
          from: 'b',
          to: 'a',
          amount: 500,
          date: DateTime(2026, 10, 3),
        ),
      ],
      asOf: DateTime.utc(2026, 10, 17),
    );
    expect(scoped.sheets['Report']!.any((r) => r.contains(10.0)), true);
    expect(scoped.sheets['Shared items'].toString(), contains('Milk'));
    expect(scoped.sheets['Shared items'].toString(), isNot(contains('Secret')));
    expect(
      scoped.sheets['My private items'].toString(),
      contains('Secret item'),
    );
    expect(
      scoped.sheets['Settlement']!.length,
      4,
    ); // no remaining transfer rows
  });
}
