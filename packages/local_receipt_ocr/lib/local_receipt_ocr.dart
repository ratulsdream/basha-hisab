import 'package:flutter/services.dart';

class LocalReceiptOcr {
  static const _channel = MethodChannel('com.bashahisab/receipt_ocr');
  Future<String> recognize(String imagePath, String dataDirectory) async =>
      await _channel.invokeMethod<String>('recognize', {
        'imagePath': imagePath,
        'dataDirectory': dataDirectory,
      }) ??
      '';
}
