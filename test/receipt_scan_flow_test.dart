import 'dart:io';
import 'package:basha_hisab/features/receipts/receipt_ocr.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_receipt_ocr/local_receipt_ocr.dart';

class _RecordingEngine extends LocalReceiptOcr {
  final paths = <String>[];
  bool fail = false;
  @override
  Future<String> recognize(String imagePath, String dataDirectory) async {
    paths.add(imagePath);
    expect(await File(imagePath).exists(), isTrue);
    for (final language in ['ell', 'eng']) {
      expect(
        await File('$dataDirectory/tessdata/$language.traineddata').length(),
        greaterThan(100000),
      );
    }
    if (fail) throw PlatformException(code: 'ocr-models');
    return 'ΑΛΦΑΜΕΓΑ\n16/10/2026\nΓΑΛΑ 2,50\nΣΥΝΟΛΟ 2,50';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, temporary, support;
  late _RecordingEngine engine;
  late ReceiptOcr scanner;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bashahisab-scan-test-');
    temporary = await Directory('${root.path}/cache').create();
    support = await Directory('${root.path}/support').create();
    engine = _RecordingEngine();
    scanner = ReceiptOcr(
      engine: engine,
      supportDirectory: () async => support,
      temporaryDirectory: () async => temporary,
    );
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
    'selected receipt reaches both OCR passes using a fresh cache directory',
    () async {
      // Reproduces the v2 failure: cache exists but cache/receipt- does not.
      expect(await Directory('${temporary.path}/receipt-').exists(), isFalse);
      final draft = await scanner.scan('test/fixtures/receipts/greek.png');
      expect(engine.paths.length, 2);
      expect(draft.total, 250);
      expect(draft.merchant, 'ΑΛΦΑΜΕΓΑ');
      expect(await temporary.list().toList(), isEmpty);
      expect(await File(engine.paths.first).exists(), isFalse);
    },
  );
  test('failed OCR also removes local temporary receipt files', () async {
    engine.fail = true;
    await expectLater(
      scanner.scan('test/fixtures/receipts/english.png'),
      throwsA(isA<PlatformException>()),
    );
    expect(engine.paths.length, 2);
    expect(await temporary.list().toList(), isEmpty);
  });
  test('file errors are distinguished from camera permission errors', () {
    expect(
      receiptScanError(const FileSystemException('failure')),
      contains('scan-files'),
    );
    expect(
      receiptScanError(PlatformException(code: 'camera_access_denied')),
      contains('scan-permission'),
    );
    expect(
      receiptScanError(PlatformException(code: 'ocr-runtime')),
      contains('scan-runtime'),
    );
  });
}
