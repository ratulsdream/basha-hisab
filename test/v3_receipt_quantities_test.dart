import 'package:basha_hisab/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('receipt quantity and unit remain explicit editable suggestions', () {
    final receipt = parseReceipt(
      'Shop\nMilk 2 x 1,25 2,50\nApples 0,500 kg x 2,00 1,00\nTOTAL 3,50',
    );
    expect(receipt.items.first.quantityMilli, 2000);
    expect(receipt.items.last.quantityMilli, 500);
    expect(receipt.items.last.unit, 'kg');
    expect(receipt.items.last.amount, 100);
  });
}
