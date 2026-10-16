import 'dart:io';
import 'package:basha_hisab/features/receipts/receipt_ocr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('EXIF rotation is baked into upright pixels', () {
    final input = img.Image(width: 120, height: 60);
    input.exif.imageIfd.orientation = 6;
    final result = preprocessReceipt(img.encodeJpg(input));
    final output = img.decodePng(result.first)!;
    expect(output.width, 60);
    expect(output.height, 120);
  });
  test(
    'Greek fixture survives both preprocessing passes without changing dimensions',
    () {
      final bytes = File('test/fixtures/receipts/greek.png').readAsBytesSync();
      final passes = preprocessReceipt(bytes);
      expect(passes.length, 2);
      for (final pass in passes) {
        final image = img.decodePng(pass)!;
        expect(image.width, 820);
        expect(image.height, 460);
      }
    },
  );
  test(
    'large images resize proportionally and invalid images fail explicitly',
    () {
      final input = img.Image(width: 3200, height: 1600);
      final passes = preprocessReceipt(img.encodePng(input));
      final output = img.decodePng(passes.first)!;
      expect(output.width, 2800);
      expect(output.height, 1400);
      expect(
        () => preprocessReceipt(File('pubspec.yaml').readAsBytesSync()),
        throwsFormatException,
      );
    },
  );
}
