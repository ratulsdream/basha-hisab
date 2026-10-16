import 'package:basha_hisab/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mixed Latin/Greek total glyphs from real OCR are normalized', () {
    expect(
      parseReceipt(
        'ΑΛΦΑΜΕΓΑ\n16/10/2026\nΓΑΛΑ 2,50\nΨΩΜΙ 1,80\nZYNOAO 4,30',
      ).total,
      430,
    );
  });
  test('Greek Cyprus receipt, comma decimals, and payment exclusions', () {
    final draft = parseReceipt(
      'ΑΛΦΑΜΕΓΑ\n16.10.26\nΓΑΛΑ 2 x 1,25 2,50\nΨΩΜΙ €1,80\nΜΕΡΙΚΟ ΣΥΝΟΛΟ 4,30\nΦΠΑ 0,20\nΕΚΠΤΩΣΗ 0,10\nΓΕΝΙΚΟ ΣΥΝΟΛΟ €4,40\nΜΕΤΡΗΤΑ 10,00\nΡΕΣΤΑ 5,60\nΚΑΡΤΑ 4,40',
    );
    expect(draft.merchant, 'ΑΛΦΑΜΕΓΑ');
    expect(draft.date, DateTime(2026, 10, 16));
    expect(draft.total, 440);
    expect(draft.items.map((i) => i.name), ['ΓΑΛΑ', 'ΨΩΜΙ']);
    expect(draft.items.map((i) => i.amount), [250, 180]);
    expect(
      draft.warnings,
      contains('Items do not add up to the receipt total'),
    );
  });
  test('Greek tonos, Greek totals and English totals', () {
    for (final keyword in [
      'TOTAL',
      'GRAND TOTAL',
      'AMOUNT DUE',
      'ΣΥΝΟΛΟ',
      'ΓΕΝΙΚΟ ΣΥΝΟΛΟ',
      'ΠΛΗΡΩΤΕΟ',
      'Πληρωτέο',
      'Σύνολο',
    ]) {
      expect(
        parseReceipt('Κατάστημα\n16-10-2026\n$keyword 12,50').total,
        1250,
        reason: keyword,
      );
    }
  });
  test('European and US thousands, currency symbols, decimal entry', () {
    for (final value in ['12.50', '12,50', '€12,50', '12,50€']) {
      expect(parseMoney(value), 1250);
    }
    for (final value in ['1.234,56', '1,234.56']) {
      expect(parseMoney(value), 123456);
    }
    for (final value in ['1,2.50', '-12,50', '1.234', '12,500', '12,34,56']) {
      expect(parseMoney(value), isNull);
    }
  });
  test('European dates, valid leap days and invalid dates', () {
    for (final date in ['16/10/2026', '16-10-2026', '16.10.2026', '16/10/26']) {
      expect(parseReceipt('Market\n$date').date, DateTime(2026, 10, 16));
    }
    expect(parseReceipt('Store\n29.02.2024').date, DateTime(2024, 2, 29));
    expect(parseReceipt('Store\n31.02.26').date, isNull);
  });
  test('English quantity receipt and wrapped total', () {
    final result = parseReceipt(
      'Fresh Market\n16/10/2026\nMilk 2 x 1.25 2.50\nBread 1.80\nSUBTOTAL 4.30\nTAX 0.20\nAMOUNT DUE\n4.50\nCARD 4.50',
    );
    expect(result.total, 450);
    expect(result.items.map((i) => i.amount), [250, 180]);
  });
  test('better complete OCR pass is selected without duplicate items', () {
    final result = selectReceiptPass(
      'SHOP\nMilk 2.50',
      'SHOP\n16/10/2026\nMilk 2.50\nTOTAL 2.50',
    );
    expect(result.total, 250);
    expect(result.items.length, 1);
    expect(result.rawText, contains('ORIGINAL IMAGE'));
    expect(result.rawText, contains('ENHANCED IMAGE'));
  });
}
