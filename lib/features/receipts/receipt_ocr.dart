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
  ReceiptOcr({
    LocalReceiptOcr? engine,
    Future<Directory> Function()? supportDirectory,
    Future<Directory> Function()? temporaryDirectory,
  }) : engine = engine ?? LocalReceiptOcr(),
       supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;
  final LocalReceiptOcr engine;
  final Future<Directory> Function() supportDirectory, temporaryDirectory;
  Future<ReceiptDraft> scan(String inputPath) async {
    final support = await supportDirectory();
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
    final temp = await temporaryDirectory();
    final workspace = await temp.createTemp('receipt-');
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

/// Do not blame camera permissions for failures that happen after image selection.
String receiptScanError(Object error) {
  if (error is FileSystemException) {
    return 'The receipt could not be prepared on this device. Check free storage and try selecting it again. (scan-files)';
  }
  if (error is FormatException) {
    return 'This image format could not be read. Choose a JPG or PNG photo, or take a new photo. (scan-format)';
  }
  if (error is MissingPluginException) {
    return 'The offline scanner is missing from this installation. Install the latest BashaHisab APK. (scan-plugin)';
  }
  if (error is PlatformException) {
    return switch (error.code) {
      'camera_access_denied' ||
      'photo_access_denied' ||
      'camera_access_restricted' ||
      'photo_access_restricted' =>
        'Allow camera/photos access in your phone settings, then try again. (scan-permission)',
      'ocr-runtime' =>
        'The offline OCR library could not start on this device. Please report this code and your phone model. (scan-runtime)',
      'ocr-models' =>
        'The Greek/English OCR models could not be loaded. Restart the app and retry. (scan-models)',
      _ =>
        'The receipt could not be read. Try a clearer photo or enter the expense manually. (scan-ocr)',
    };
  }
  return 'The receipt could not be scanned. Try another photo or enter the expense manually. (scan-unknown)';
}
