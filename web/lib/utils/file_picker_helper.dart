// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/services.dart';

void pickZipFile(void Function(Uint8List bytes, String filename) onFilePicked) {
  final uploadInput = html.FileUploadInputElement()..accept = '.zip';
  uploadInput.click();
  uploadInput.onChange.listen((_) {
    final files = uploadInput.files;
    if (files != null && files.isNotEmpty) {
      final file = files[0];
      final reader = html.FileReader();
      reader.onLoadEnd.listen((_) {
        final result = reader.result;
        if (result is Uint8List) {
          onFilePicked(result, file.name);
        } else if (result is ByteBuffer) {
          onFilePicked(result.asUint8List(), file.name);
        }
      });
      reader.readAsArrayBuffer(file);
    }
  });
}

void pickWorldFile(void Function(Uint8List bytes, String filename) onFilePicked) {
  final uploadInput = html.FileUploadInputElement()..accept = '.world,.gzip,.zip';
  uploadInput.click();
  uploadInput.onChange.listen((_) {
    final files = uploadInput.files;
    if (files != null && files.isNotEmpty) {
      final file = files[0];
      final reader = html.FileReader();
      reader.onLoadEnd.listen((_) {
        final result = reader.result;
        if (result is Uint8List) {
          onFilePicked(result, file.name);
        } else if (result is ByteBuffer) {
          onFilePicked(result.asUint8List(), file.name);
        }
      });
      reader.readAsArrayBuffer(file);
    }
  });
}

void downloadFile(String url, String filename) {
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  html.document.body?.children.remove(anchor);
}

void downloadTextFile(String content, String filename) {
  final blob = html.Blob([content], 'text/plain;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  html.document.body?.children.remove(anchor);
  html.Url.revokeObjectUrl(url);
}

Future<bool> copyTextToClipboard(String text) async {
  // 1. Try Flutter framework's native Clipboard.setData
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (_) {}

  // 2. Try modern navigator.clipboard API if available
  try {
    if (html.window.navigator.clipboard != null) {
      await html.window.navigator.clipboard!.writeText(text);
      return true;
    }
  } catch (_) {}

  // 3. Fallback using textarea + execCommand('copy') which works universally on HTTP and HTTPS
  try {
    final textarea = html.TextAreaElement()
      ..value = text
      ..setAttribute('readonly', '')
      ..style.position = 'fixed'
      ..style.top = '0'
      ..style.left = '0'
      ..style.width = '2em'
      ..style.height = '2em'
      ..style.padding = '0'
      ..style.border = 'none'
      ..style.outline = 'none'
      ..style.boxShadow = 'none'
      ..style.background = 'transparent';
    html.document.body?.append(textarea);
    textarea.focus();
    textarea.select();
    textarea.setSelectionRange(0, text.length);
    final success = html.document.execCommand('copy');
    textarea.remove();
    if (success == true) return true;
  } catch (_) {}

  return false;
}
