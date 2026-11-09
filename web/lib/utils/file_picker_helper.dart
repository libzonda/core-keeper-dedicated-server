// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

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
