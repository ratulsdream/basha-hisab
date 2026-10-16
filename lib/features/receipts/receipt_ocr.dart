import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:local_receipt_ocr/local_receipt_ocr.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain.dart';

/// CPU work runs off the UI isolate. Bake EXIF before resizing; limit peak memory.
List<Uint8List> preprocessReceipt(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported receipt image');
  var original = img.bakeOrientation(decoded);
  final longest = original.width > original.height
      ? original.width
      : original.height;
  if (longest > 2800) {
    original = img.copyResize(
      original,
      width: original.width >= original.height ? 2800 : null,
      height: original.height > original.width ? 2800 : null,
      interpolation: img.Interpolation.cubic,
    );
  }
  // Contrast-normalized grayscale preserves faint thermal print; a hard threshold
  // is deliberately avoided because it can erase pale Greek diacritics.
  var enhanced = img.grayscale(original.clone());
  enhanced = img.normalize(enhanced, min: 0, max: 255);
  enhanced = img.adjustColor(enhanced, contrast: 1.15);
  enhanced = img.convolution(enhanced, filter: [0, -1, 0, -1, 5, -1, 0, -1, 0]);
  return [img.encodePng(original), img.encodePng(enhanced)];
}

class ReceiptOcr {
  ReceiptOcr({LocalReceiptOcr? engine}) : engine = engine ?? LocalReceiptOcr();
  final LocalReceiptOcr engine;
  Future<ReceiptDraft> scan(String inputPath) async {
    final support = await getApplicationSupportDirectory();
    final dataRoot = Directory('${support.path}/ocr-v2');
    final tessdata = Directory('${dataRoot.path}/tessdata');
    await tessdata.create(recursive: true);
    for (final language in ['ell', 'eng']) {
      final file = File('${tessdata.path}/$language.traineddata');
      if (!await file.exists()) {
        final model = await rootBundle.load(
          'assets/tessdata/$language.traineddata',
        );
        final pending = File('${file.path}.tmp');
        await pending.writeAsBytes(model.buffer.asUint8List(), flush: true);
        await pending.rename(file.path);
      }
    }
    final temp = await getTemporaryDirectory();
    final workspace = await Directory('${temp.path}/receipt-').createTemp();
    try {
      final images = await compute(
        preprocessReceipt,
        await File(inputPath).readAsBytes(),
      );
      final texts = <String>[];
      Object? lastError;
      for (var index = 0; index < images.length; index++) {
        final file = File('${workspace.path}/$index.png');
        await file.writeAsBytes(images[index]);
        try {
          texts.add(await engine.recognize(file.path, dataRoot.path));
        } catch (error) {
          texts.add('');
          lastError = error;
        }
      }
      if (texts.every((text) => text.trim().isEmpty) && lastError != null) {
        throw lastError;
      }
      return selectReceiptPass(texts[0], texts[1]);
    } finally {
      // Image derivatives never reach Firestore and do not accumulate in app storage.
      await workspace.delete(recursive: true);
    }
  }
}
