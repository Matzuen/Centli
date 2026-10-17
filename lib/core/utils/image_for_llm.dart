import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Preprocess a screenshot for LLM vision upload.
({Uint8List bytes, int width, int height}) prepareImageForLlm(
  Uint8List raw, {
  int maxEdge = 1600,
  int quality = 80,
  int maxBase64Bytes = 2 * 1024 * 1024,
}) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    throw StateError('无法解码图片');
  }
  img.Image work = decoded;
  final longest = math.max(work.width, work.height);
  if (longest > maxEdge) {
    final scale = maxEdge / longest;
    work = img.copyResize(
      work,
      width: (work.width * scale).round(),
      height: (work.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  var q = quality;
  Uint8List jpeg = Uint8List.fromList(img.encodeJpg(work, quality: q));
  while (base64Encode(jpeg).length > maxBase64Bytes && q > 40) {
    q -= 10;
    jpeg = Uint8List.fromList(img.encodeJpg(work, quality: q));
  }
  if (base64Encode(jpeg).length > maxBase64Bytes) {
    throw StateError('图片过大，请重试');
  }
  return (bytes: jpeg, width: work.width, height: work.height);
}
