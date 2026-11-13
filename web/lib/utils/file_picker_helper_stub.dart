import 'package:flutter/services.dart';

void pickZipFile(void Function(Uint8List bytes, String filename) onFilePicked) {
  // Desktop stub
}

void pickWorldFile(void Function(Uint8List bytes, String filename) onFilePicked) {
  // Desktop stub
}

void downloadFile(String url, String filename) {
  // Desktop stub
}

void downloadTextFile(String content, String filename) {
  // Desktop stub
}

Future<bool> copyTextToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}
