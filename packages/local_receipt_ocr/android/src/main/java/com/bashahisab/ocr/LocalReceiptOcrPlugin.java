package com.bashahisab.ocr;

import android.os.Handler;
import android.os.Looper;
import com.googlecode.tesseract.android.TessBaseAPI;
import java.io.File;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodChannel;

/** One engine per operation, serialized off the UI thread; no network APIs. */
public final class LocalReceiptOcrPlugin implements FlutterPlugin {
    private MethodChannel channel;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "com.bashahisab/receipt_ocr");
        channel.setMethodCallHandler((call, result) -> {
            if (!call.method.equals("recognize")) { result.notImplemented(); return; }
            final String image = call.argument("imagePath");
            final String directory = call.argument("dataDirectory");
            if (image == null || directory == null) { result.error("arguments", "Missing image or language data", null); return; }
            worker.execute(() -> {
                TessBaseAPI engine = new TessBaseAPI();
                try {
                    if (!engine.init(directory, "ell+eng", TessBaseAPI.OEM_LSTM_ONLY))
                        throw new IllegalStateException("Could not load bundled Greek/English models");
                    engine.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO);
                    engine.setVariable("preserve_interword_spaces", "1");
                    engine.setImage(new File(image));
                    String text = engine.getUTF8Text();
                    main.post(() -> result.success(text));
                } catch (Exception error) {
                    main.post(() -> result.error("ocr", "Could not recognize this receipt", null));
                } finally { engine.recycle(); }
            });
        });
    }
    @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        worker.shutdown();
    }
}
