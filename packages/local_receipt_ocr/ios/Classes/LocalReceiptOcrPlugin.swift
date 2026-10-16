import Flutter
import UIKit
import libtesseract

public class LocalReceiptOcrPlugin: NSObject, FlutterPlugin {
    private let worker = DispatchQueue(label: "com.bashahisab.ocr")
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.bashahisab/receipt_ocr", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(LocalReceiptOcrPlugin(), channel: channel)
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "recognize" else { result(FlutterMethodNotImplemented); return }
        guard let args = call.arguments as? [String: String],
              let imagePath = args["imagePath"], let directory = args["dataDirectory"] else {
            result(FlutterError(code: "arguments", message: "Missing receipt or language data", details: nil)); return
        }
        worker.async {
            guard let engine = TessBaseAPICreate() else {
                DispatchQueue.main.async { result(FlutterError(code: "ocr", message: "OCR engine unavailable", details: nil)) }; return
            }
            defer { TessBaseAPIEnd(engine); TessBaseAPIDelete(engine) }
            // Tesseract C API takes the tessdata directory itself on iOS.
            let path = (directory as NSString).appendingPathComponent("tessdata")
            guard TessBaseAPIInit2(engine, path, "ell+eng", OEM_LSTM_ONLY) == 0 else {
                DispatchQueue.main.async { result(FlutterError(code: "ocr", message: "Could not load Greek/English models", details: nil)) }; return
            }
            guard let pixels = pixRead(imagePath) else {
                DispatchQueue.main.async { result(FlutterError(code: "ocr", message: "Could not read receipt", details: nil)) }; return
            }
            var ownedPixels: UnsafeMutablePointer<PIX>? = pixels
            defer { pixDestroy(&ownedPixels) }
            TessBaseAPISetPageSegMode(engine, PSM_AUTO)
            TessBaseAPISetVariable(engine, "preserve_interword_spaces", "1")
            TessBaseAPISetImage2(engine, pixels)
            guard let output = TessBaseAPIGetUTF8Text(engine) else {
                DispatchQueue.main.async { result(FlutterError(code: "ocr", message: "Receipt unreadable", details: nil)) }; return
            }
            let text = String(cString: output)
            TessDeleteText(output)
            DispatchQueue.main.async { result(text) }
        }
    }
}
