import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// On-device Chinese OCR for bill screenshots.
class BillOcrService {
  TextRecognizer? _recognizer;

  TextRecognizer get _r {
    return _recognizer ??= TextRecognizer(
      script: TextRecognitionScript.chinese,
    );
  }

  /// Recognize Chinese text from an image file path.
  Future<String> recognizeChinese(String path) async {
    if (kIsWeb) {
      throw UnsupportedError('文字识别不支持 Web');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('图片不存在: $path');
    }
    final input = InputImage.fromFilePath(path);
    final recognized = await _r.processImage(input);
    return recognized.text;
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
